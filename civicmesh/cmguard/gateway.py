"""The ASGI front door in front of jac-scale.

jac-scale listens on 127.0.0.1 only; this gateway is the one public port. It
exists because the framework's own surface is wider than the app needs and
has no request limits: every walker in the entry module is an endpoint, API
keys and scheduler jobs have routes, and an anonymous client-error route
wrote any text into the logs (a 2 MB body froze the server for minutes).

For every request, in order:
  1. route allowlist: the eleven walkers the client uses, sign-up, login, the
     token check, health, static files; everything else is a 404
  2. body size cap per route (from Content-Length, then while reading), a read
     deadline, and JSON shape caps (depth, node count, string length)
  3. walkers need a valid login token, verified here (HS256, the server's
     secret) before anything reaches jac-scale
  4. token buckets per client address, per visitor and server-wide, stricter
     for model-backed walkers and sign-up
  5. duplicate collapse: identical requests from one visitor share a single
     upstream call and reuse its answer briefly
  6. concurrency caps per address, server-wide and for model-backed walkers,
     with a short queue, then 503
  7. an upstream timeout per route; errors come back as generic JSON

Nothing here logs an address, a visitor id or a request body: only aggregate
counters (cmguard/telemetry.py).
"""

import asyncio
import hashlib
import json
import os
import time

import httpx

from cmguard import telemetry
from cmguard.clientip import client_ip
from cmguard.config import GatewayConfig
from cmguard.limits import InflightCounter, TokenBuckets

# The walkers the browser client calls, and the limit class for each. Every
# other walker (Eligibility, Navigation, Escalation, Pathfinder, Critique) is
# spawned by IntakeWalker on the server and is not reachable from outside.
PUBLIC_WALKERS = {
    "IntakeWalker": "chat",
    "NarrateWalker": "model",
    "LocalizeWalker": "model",
    "LocalHelpWalker": "external",
    "SeedWalker": "seed",
    "ForgetWalker": "forget",
    "MemoryWalker": "light",
    "GraphSnapshotWalker": "light",
    "ImpactWalker": "light",
    "PlatformWalker": "light",
    "ReflectionReadWalker": "light",
}
API_CLASSES = {"register", "login", "me", "chat", "model", "external", "light", "seed", "forget"}
AUTH_CLASSES = {"me", "chat", "model", "external", "light", "seed", "forget"}
DEDUP_CLASSES = {"chat", "model"}
BLOCKED_PREFIXES = (
    "/admin", "/api-key", "/jobs", "/sso", "/function", "/graph", "/redoc",
    "/metrics", "/user/password", "/ws", "/websocket", "/webhook",
)
# Read-only API documentation stays available (the command palette's "Show
# /docs OpenAPI" action). It lists routes the gateway refuses; listing them
# grants nothing.
DOC_PATHS = ("/docs", "/docs/oauth2-redirect", "/openapi.json")
HOP_HEADERS = {
    b"connection", b"keep-alive", b"proxy-authenticate", b"proxy-authorization", b"te", b"trailer",
    b"transfer-encoding", b"upgrade", b"content-length", b"host", b"x-forwarded-for", b"x-real-ip",
    b"forwarded", b"x-forwarded-host", b"x-forwarded-proto", b"x-forwarded-port",
}
SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"referrer-policy", b"no-referrer"),
    (b"permissions-policy", b"camera=(), microphone=(), geolocation=(), payment=(), usb=()"),
]


STARTING_PAGE = (b"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta http-equiv='refresh' content='3'>"
                 b"<meta name='viewport' content='width=device-width, initial-scale=1'><title>CivicMesh is starting</title></head>"
                 b"<body style='font-family:system-ui;background:#0a0a0a;color:#eee;display:grid;place-items:center;min-height:90vh'>"
                 b"<p>CivicMesh is starting&hellip; this page refreshes by itself. In danger now: call 911. Crisis: call or text 988.</p></body></html>")


def classify(method: str, path: str):
    """(route class, walker name or None). 'blocked' and 'sink' are special."""
    if path.startswith("/walker/"):
        name = path[len("/walker/"):]
        if "/" in name or name not in PUBLIC_WALKERS or method not in ("POST", "OPTIONS"):
            return "blocked", None
        return PUBLIC_WALKERS[name], name
    if path == "/cl/__error__":
        return ("sink", None) if method == "POST" else ("blocked", None)
    if path == "/user/register":
        return ("register", None) if method in ("POST", "OPTIONS") else ("blocked", None)
    if path in ("/user/login", "/user/refresh-token"):
        return ("login", None) if method in ("POST", "OPTIONS") else ("blocked", None)
    if path == "/user/me":
        return ("me", None) if method in ("GET", "OPTIONS") else ("blocked", None)
    if path.startswith("/user/"):
        return "blocked", None
    if path in ("/healthz", "/healthz/live", "/healthz/ready"):
        return ("health", None) if method in ("GET", "HEAD") else ("blocked", None)
    if path in DOC_PATHS:
        return ("static", None) if method in ("GET", "HEAD") else ("blocked", None)
    for prefix in BLOCKED_PREFIXES:
        if path == prefix or path.startswith(prefix + "/") or path.startswith(prefix + "?"):
            return "blocked", None
    if method in ("GET", "HEAD"):
        return "static", None
    return "blocked", None


def json_shape_problem(obj, max_depth: int, max_nodes: int, max_string: int) -> str:
    """'' if the parsed JSON is within the caps, else what's wrong."""
    stack = [(obj, 1)]
    nodes = 0
    while stack:
        item, depth = stack.pop()
        nodes += 1
        if nodes > max_nodes:
            return "too many JSON values"
        if depth > max_depth:
            return "JSON nested too deeply"
        if isinstance(item, str):
            if len(item) > max_string:
                return "JSON string too long"
        elif isinstance(item, dict):
            for key, value in item.items():
                if len(str(key)) > 256:
                    return "JSON key too long"
                stack.append((value, depth + 1))
        elif isinstance(item, list):
            for value in item:
                stack.append((value, depth + 1))
    return ""


class TooLarge(Exception):
    pass


class Disconnected(Exception):
    pass


def error_body(status: int, code: str, message: str) -> bytes:
    return json.dumps({
        "ok": False, "type": "error", "data": None,
        "error": {"code": code, "message": message},
        "meta": {"extra": {"http_status": status}},
    }).encode()


class Gateway:
    def __init__(self, cfg: "GatewayConfig | None" = None, jwt_secret: "str | None" = None):
        self.cfg = cfg or GatewayConfig()
        self.jwt_secret = jwt_secret if jwt_secret is not None else os.environ.get("CIVICMESH_JWT_SECRET", "")
        mk = self.cfg.max_keys
        self.buckets = {}
        for cls, scopes in self.cfg.rates.items():
            for scope, rate in scopes.items():
                if rate:
                    self.buckets[(cls, scope)] = TokenBuckets(rate[0], rate[1], mk)
        self.per_ip = InflightCounter(self.cfg.inflight_per_ip, mk)
        self.global_slots = None
        self.model_slots = None
        self.client = None
        self.ready = False
        self._inflight = {}
        self._recent = {}
        self._tasks = []

    # -- ASGI entry --------------------------------------------------------
    async def __call__(self, scope, receive, send):
        kind = scope["type"]
        if kind == "lifespan":
            await self._lifespan(receive, send)
            return
        if kind == "websocket":
            # The app has no WebSocket clients; refuse the framework's routes.
            telemetry.count("rejected:websocket")
            await send({"type": "websocket.close", "code": 1008})
            return
        if kind != "http":
            return
        try:
            await self._http(scope, receive, send)
        except Disconnected:
            telemetry.count("client_disconnected")
        except Exception as ex:  # never leak internals
            telemetry.count("gateway_error:" + type(ex).__name__)
            try:
                await self._respond(send, 500, error_body(500, "INTERNAL", "Something went wrong. Please try again."))
            except Exception:
                pass

    async def _lifespan(self, receive, send):
        while True:
            msg = await receive()
            if msg["type"] == "lifespan.startup":
                await self.startup()
                await send({"type": "lifespan.startup.complete"})
            elif msg["type"] == "lifespan.shutdown":
                await self.shutdown()
                await send({"type": "lifespan.shutdown.complete"})
                return

    async def startup(self):
        self.global_slots = asyncio.Semaphore(self.cfg.inflight_global)
        self.model_slots = asyncio.Semaphore(self.cfg.inflight_model)
        self.client = httpx.AsyncClient(
            base_url=self.cfg.upstream,
            limits=httpx.Limits(max_connections=self.cfg.inflight_global + 64, max_keepalive_connections=32),
            timeout=httpx.Timeout(30.0, connect=5.0),
            follow_redirects=False,
        )
        self._tasks.append(asyncio.create_task(self._watch_ready()))
        self._tasks.append(asyncio.create_task(self._telemetry_loop()))

    async def shutdown(self):
        for t in self._tasks:
            t.cancel()
        if self.client:
            await self.client.aclose()

    async def _watch_ready(self):
        while True:
            try:
                r = await self.client.get("/healthz", timeout=3.0)
                ok = r.status_code < 500
            except Exception:
                ok = False
            if ok and not self.ready:
                self.ready = True
            await asyncio.sleep(1.0 if not self.ready else 15.0)

    async def _telemetry_loop(self):
        while True:
            await asyncio.sleep(max(5.0, self.cfg.telemetry_interval_s / 4))
            telemetry.maybe_log(self.cfg.telemetry_interval_s, "gateway")

    # -- request handling --------------------------------------------------
    async def _http(self, scope, receive, send):
        method = scope["method"].upper()
        path = scope.get("path", "/") or "/"
        headers = {k.lower(): v for k, v in scope.get("headers", [])}
        cls, walker = classify(method, path)
        if cls == "blocked":
            telemetry.count("rejected:blocked_route")
            await self._respond(send, 404, error_body(404, "NOT_FOUND", "Not found."))
            return
        peer = (scope.get("client") or ("unknown", 0))[0]
        ip = client_ip(peer, headers.get(b"x-forwarded-for", b"").decode("latin-1"), self.cfg.trusted_hops)

        if not self.ready and cls != "health":
            telemetry.count("rejected:starting")
            if cls == "static":
                await self._respond(send, 503, STARTING_PAGE, extra=[(b"retry-after", b"3")],
                                    headers_raw=[(b"content-type", b"text/html; charset=utf-8"), (b"cache-control", b"no-store")])
            else:
                await self._respond(send, 503, error_body(503, "STARTING", "CivicMesh is starting. Try again in a few seconds."),
                                    extra=[(b"retry-after", b"3")])
            return

        # Body: cap by the declared length, then while reading.
        limit = self.cfg.body_bytes.get(cls, 0)
        declared = headers.get(b"content-length")
        if declared is not None:
            try:
                if int(declared) > limit:
                    telemetry.count("rejected:body_too_large:" + cls)
                    await self._respond(send, 413, error_body(413, "PAYLOAD_TOO_LARGE", "That request is too large."))
                    return
            except ValueError:
                await self._respond(send, 400, error_body(400, "BAD_REQUEST", "Bad request."))
                return
        body = b""
        if method in ("POST", "PUT", "PATCH"):
            try:
                body = await self._read_body(receive, limit)
            except TooLarge:
                telemetry.count("rejected:body_too_large:" + cls)
                await self._respond(send, 413, error_body(413, "PAYLOAD_TOO_LARGE", "That request is too large."))
                return
            except asyncio.TimeoutError:
                telemetry.count("rejected:body_timeout:" + cls)
                await self._respond(send, 408, error_body(408, "TIMEOUT", "The request took too long to send."))
                return

        # Client error reports: acknowledged, counted, never forwarded or logged.
        if cls == "sink":
            if self._limited(cls, ip, None):
                telemetry.count("rejected:rate_limited:sink")
            else:
                telemetry.count("client_error_report_dropped")
            await self._respond(send, 200, b'{"ok":true}')
            return

        user = None
        if method != "OPTIONS" and cls in API_CLASSES:
            if body:
                try:
                    parsed = json.loads(body)
                except Exception:
                    telemetry.count("rejected:bad_json:" + cls)
                    await self._respond(send, 400, error_body(400, "BAD_REQUEST", "The request body must be JSON."))
                    return
                problem = json_shape_problem(parsed, self.cfg.json_max_depth, self.cfg.json_max_nodes, self.cfg.json_max_string)
                if not problem and walker and not isinstance(parsed, dict):
                    problem = "walker fields must be a JSON object"
                if problem:
                    telemetry.count("rejected:json_shape:" + cls)
                    await self._respond(send, 400, error_body(400, "BAD_REQUEST", problem))
                    return
            if cls in AUTH_CLASSES:
                user = self._visitor(headers.get(b"authorization", b"").decode("latin-1"))
                if not user:
                    telemetry.count("rejected:unauthenticated:" + cls)
                    await self._respond(send, 401, error_body(401, "UNAUTHORIZED", "Please sign in again."))
                    return

        wait = self._limited(cls, ip, user)
        if wait:
            await self._respond(send, 429, error_body(429, "RATE_LIMITED", "Too many requests. Please wait a moment and try again."),
                                extra=[(b"retry-after", str(int(wait + 0.999)).encode())])
            return

        if cls in API_CLASSES:
            await self._api(scope, send, headers, body, cls, ip, user)
        else:
            await self._stream(scope, send, headers, body, cls, ip)

    def _visitor(self, auth: str) -> str:
        """Verified visitor id from the bearer token, or ''."""
        if not auth.lower().startswith("bearer "):
            return ""
        token = auth[7:].strip()
        if not token or len(token) > 4096:
            return ""
        if not self.jwt_secret:
            # No secret shared with the gateway (local runs): jac-scale still
            # verifies the token; limit per token instead of per visitor.
            return "t:" + hashlib.sha256(token.encode()).hexdigest()[:24]
        try:
            import jwt as pyjwt

            claims = pyjwt.decode(token, self.jwt_secret, algorithms=["HS256"])
        except Exception:
            return ""
        uid = str(claims.get("user_id") or "")
        return ("u:" + hashlib.sha256(uid.encode()).hexdigest()[:24]) if uid else ""

    def _limited(self, cls: str, ip: str, user: "str | None") -> float:
        """0 if allowed; otherwise seconds to wait (and the rejection is counted)."""
        for scope, key in (("ip", ip), ("user", user), ("global", "*")):
            if scope == "user" and not user:
                continue
            bucket = self.buckets.get((cls, scope))
            if bucket is None:  # (an empty TokenBuckets is falsy: it has __len__)
                continue
            ok, wait = bucket.take(key)
            if not ok:
                telemetry.count(f"rejected:rate_{scope}:{cls}")
                return wait
        return 0.0

    async def _read_body(self, receive, limit: int) -> bytes:
        deadline = time.monotonic() + self.cfg.body_read_s
        chunks = []
        size = 0
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise asyncio.TimeoutError()
            msg = await asyncio.wait_for(receive(), timeout=remaining)
            if msg["type"] == "http.disconnect":
                raise Disconnected()
            part = msg.get("body", b"")
            size += len(part)
            if size > limit:
                raise TooLarge()
            chunks.append(part)
            if not msg.get("more_body"):
                return b"".join(chunks)

    def _upstream_headers(self, headers: dict, body: bytes):
        out = [(k, v) for k, v in headers.items() if k not in HOP_HEADERS]
        if body:
            out.append((b"content-length", str(len(body)).encode()))
        return out

    async def _acquire(self, sem) -> bool:
        try:
            await asyncio.wait_for(sem.acquire(), timeout=self.cfg.queue_wait_s)
            return True
        except asyncio.TimeoutError:
            return False

    async def _api(self, scope, send, headers, body, cls, ip, user):
        key = None
        if cls in DEDUP_CLASSES and user:
            key = hashlib.sha256((cls + "|" + user + "|" + scope["path"] + "|").encode() + body).hexdigest()
            self._sweep_recent()
            cached = self._recent.get(key)
            if cached and cached[0] > time.monotonic():
                telemetry.count("dedup_hit:" + cls)
                await self._respond(send, cached[1], cached[3], headers_raw=cached[2])
                return
            pending = self._inflight.get(key)
            if pending is not None:
                telemetry.count("dedup_joined:" + cls)
                status, raw, payload = await asyncio.shield(pending)
                await self._respond(send, status, payload, headers_raw=raw)
                return
        future = asyncio.get_running_loop().create_future() if key else None
        if key:
            self._inflight[key] = future
        try:
            status, raw, payload = await self._forward_api(scope, headers, body, cls, ip)
        except BaseException as ex:
            if future is not None:
                future.set_result((502, [(b"content-type", b"application/json")],
                                   error_body(502, "UPSTREAM", "The service is busy. Please try again.")))
                self._inflight.pop(key, None)
            raise ex
        if future is not None:
            future.set_result((status, raw, payload))
            self._inflight.pop(key, None)
            if status == 200:
                self._remember(key, cls, status, raw, payload)
        await self._respond(send, status, payload, headers_raw=raw)

    def _sweep_recent(self):
        """Drop expired answer copies (held at most a minute, memory only)."""
        now = time.monotonic()
        while self._recent:
            k = next(iter(self._recent))
            if self._recent[k][0] > now and len(self._recent) <= 4000:
                break
            self._recent.pop(k, None)

    def _remember(self, key, cls, status, raw, payload):
        self._sweep_recent()
        self._recent[key] = (time.monotonic() + self.cfg.dedup_ttl_s.get(cls, 0.0), status, raw, payload)

    async def _forward_api(self, scope, headers, body, cls, ip):
        busy = (503, [(b"content-type", b"application/json"), (b"retry-after", b"2")],
                error_body(503, "BUSY", "CivicMesh is busy right now. Please try again in a moment."))
        if not self.per_ip.acquire(ip):
            telemetry.count("rejected:inflight_ip:" + cls)
            return busy
        got_global = got_model = False
        try:
            got_global = await self._acquire(self.global_slots)
            if not got_global:
                telemetry.count("rejected:inflight_global:" + cls)
                return busy
            if cls == "model":
                got_model = await self._acquire(self.model_slots)
                if not got_model:
                    telemetry.count("rejected:inflight_model")
                    return busy
            telemetry.count("allowed:" + cls)
            url = scope["path"] + (("?" + scope["query_string"].decode("latin-1")) if scope.get("query_string") else "")
            try:
                r = await self.client.request(
                    scope["method"], url, content=body or None,
                    headers=self._upstream_headers(headers, body),
                    timeout=httpx.Timeout(self.cfg.timeout_s.get(cls, 30.0), connect=5.0),
                )
            except httpx.TimeoutException:
                telemetry.count("upstream_timeout:" + cls)
                return (504, [(b"content-type", b"application/json")],
                        error_body(504, "TIMEOUT", "That took too long. Please try again."))
            except httpx.HTTPError:
                telemetry.count("upstream_error:" + cls)
                return (502, [(b"content-type", b"application/json")],
                        error_body(502, "UPSTREAM", "The service is busy. Please try again."))
            raw = [(k.encode("latin-1"), v.encode("latin-1")) for k, v in r.headers.items()
                   if k.lower().encode() not in HOP_HEADERS and k.lower() != "content-encoding"]
            return r.status_code, raw, r.content
        finally:
            if got_model:
                self.model_slots.release()
            if got_global:
                self.global_slots.release()
            self.per_ip.release(ip)

    async def _stream(self, scope, send, headers, body, cls, ip):
        """Static files and pages: streamed through, per-address rate limited."""
        telemetry.count("allowed:" + cls)
        url = scope["path"] + (("?" + scope["query_string"].decode("latin-1")) if scope.get("query_string") else "")
        req = self.client.build_request(scope["method"], url, headers=self._upstream_headers(headers, body),
                                        content=body or None,
                                        timeout=httpx.Timeout(self.cfg.timeout_s.get(cls, 30.0), connect=5.0))
        try:
            r = await self.client.send(req, stream=True)
        except httpx.HTTPError:
            telemetry.count("upstream_error:" + cls)
            await self._respond(send, 502, error_body(502, "UPSTREAM", "The service is busy. Please try again."))
            return
        try:
            raw = list(r.headers.raw)
            raw = [(k, v) for k, v in raw if k.lower() not in HOP_HEADERS or k.lower() == b"content-length"]
            await send({"type": "http.response.start", "status": r.status_code, "headers": raw + SECURITY_HEADERS})
            async for chunk in r.aiter_raw():
                await send({"type": "http.response.body", "body": chunk, "more_body": True})
            await send({"type": "http.response.body", "body": b"", "more_body": False})
        finally:
            await r.aclose()

    async def _respond(self, send, status: int, payload: bytes, extra=None, headers_raw=None):
        hdrs = list(headers_raw) if headers_raw is not None else [(b"content-type", b"application/json")]
        hdrs = [(k, v) for k, v in hdrs if k.lower() != b"content-length"]
        hdrs.append((b"content-length", str(len(payload)).encode()))
        if headers_raw is None:
            hdrs.append((b"cache-control", b"no-store"))
        await send({"type": "http.response.start", "status": status, "headers": hdrs + SECURITY_HEADERS + list(extra or [])})
        await send({"type": "http.response.body", "body": payload, "more_body": False})


app = Gateway()
