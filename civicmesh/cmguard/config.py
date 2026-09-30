"""Every abuse-protection threshold, read from the environment.

Defaults are sized for a free Hugging Face Space (2 vCPU, one process) and sit
well above what a real person does: a visitor sends a chat turn every few
seconds at most, and each turn triggers at most three optional model calls.
A shared address (a library, a shelter, a school) gets many times one
visitor's allowance. docs/DEPLOY.md lists every variable.

Rate limits are written "COUNT/SECONDS" and can be overridden per route class
and scope, e.g. CIVICMESH_RL_CHAT_IP=60/60.
"""

import os


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, "").strip() or default)
    except ValueError:
        return default


def env_str(name: str, default: str) -> str:
    return os.environ.get(name, "").strip() or default


def parse_rate(spec: str):
    """'30/60' -> (30.0, 60.0): 30 requests per 60 seconds (burst of 30)."""
    count, _, seconds = spec.partition("/")
    return float(count), float(seconds or 60)


# Route classes. Each scope ("ip", "user", "global") is a token bucket;
# None means that scope isn't limited for the class.
DEFAULT_RATES = {
    # Per-address limits are generous on purpose: a library, shelter or school
    # can put many people behind one address. Per-visitor limits are what one
    # person could plausibly do. The model budget (BudgetConfig) caps spend
    # however requests are spread.
    #            per client address   per signed-in visitor   whole server
    "static":   {"ip": "600/60",     "user": None,           "global": "12000/60"},
    "health":   {"ip": "60/60",      "user": None,           "global": "600/60"},
    "register": {"ip": "20/600",     "user": None,           "global": "200/600"},
    "login":    {"ip": "60/600",     "user": None,           "global": "900/600"},
    "me":       {"ip": "180/60",     "user": "40/60",        "global": "3000/60"},
    # A caseworker trying phrasings can send a turn every couple of seconds;
    # an account hammering past that is still capped by its address and the
    # server-wide bucket.
    "chat":     {"ip": "90/60",      "user": "40/60",        "global": "600/60"},
    "model":    {"ip": "60/60",      "user": "12/60",        "global": "180/60"},
    "external": {"ip": "30/60",      "user": "8/60",         "global": "200/60"},
    "light":    {"ip": "240/60",     "user": "60/60",        "global": "4000/60"},
    "seed":     {"ip": "40/600",     "user": "6/600",        "global": "400/600"},
    "forget":   {"ip": "20/600",     "user": "4/600",        "global": "200/600"},
    "sink":     {"ip": "10/60",      "user": None,           "global": "120/60"},
}

# Largest request body per class, in bytes (checked before it is read).
DEFAULT_BODY_BYTES = {
    "register": 2048, "login": 2048, "me": 0, "chat": 65536, "model": 32768,
    "external": 8192, "light": 8192, "seed": 4096, "forget": 4096, "sink": 8192,
    "static": 0, "health": 0,
}

# Upstream timeout per class, seconds.
DEFAULT_TIMEOUT_S = {
    "static": 30.0, "health": 5.0, "register": 15.0, "login": 15.0, "me": 10.0,
    "chat": 40.0, "model": 60.0, "external": 30.0, "light": 20.0, "seed": 30.0,
    "forget": 20.0,
}


class GatewayConfig:
    def __init__(self):
        self.upstream = env_str("CIVICMESH_UPSTREAM", "http://127.0.0.1:8000")
        # Hugging Face's proxy appends the caller's address to X-Forwarded-For
        # (verified: a spoofed left entry is kept, the real one is appended),
        # so exactly one hop is trusted, and only when the direct peer is a
        # private address (the proxy), never a public one.
        self.trusted_hops = env_int("CIVICMESH_TRUSTED_PROXY_HOPS", 1)
        self.rates = {}
        for cls, scopes in DEFAULT_RATES.items():
            self.rates[cls] = {}
            for scope, spec in scopes.items():
                override = os.environ.get(f"CIVICMESH_RL_{cls.upper()}_{scope.upper()}", "").strip()
                spec = override or spec
                self.rates[cls][scope] = parse_rate(spec) if spec and spec.lower() != "off" else None
        self.body_bytes = {k: env_int(f"CIVICMESH_BODY_MAX_{k.upper()}", v) for k, v in DEFAULT_BODY_BYTES.items()}
        self.timeout_s = {k: env_float(f"CIVICMESH_TIMEOUT_{k.upper()}", v) for k, v in DEFAULT_TIMEOUT_S.items()}
        # JSON shape caps for API bodies.
        self.json_max_depth = env_int("CIVICMESH_JSON_MAX_DEPTH", 12)
        self.json_max_nodes = env_int("CIVICMESH_JSON_MAX_NODES", 5000)
        self.json_max_string = env_int("CIVICMESH_JSON_MAX_STRING", 20000)
        # Concurrency: API requests in flight to jac-scale, per address and in
        # total; model-backed requests have their own, smaller pool.
        self.inflight_per_ip = env_int("CIVICMESH_INFLIGHT_PER_IP", 6)
        self.inflight_global = env_int("CIVICMESH_INFLIGHT_GLOBAL", 16)
        self.inflight_model = env_int("CIVICMESH_INFLIGHT_MODEL", 6)
        self.queue_wait_s = env_float("CIVICMESH_QUEUE_WAIT_S", 3.0)
        self.body_read_s = env_float("CIVICMESH_BODY_READ_S", 15.0)
        # Duplicate collapse: identical requests from the same visitor share
        # one upstream call while it runs, and reuse its answer this long.
        self.dedup_ttl_s = {"chat": env_float("CIVICMESH_DEDUP_CHAT_S", 3.0),
                            "model": env_float("CIVICMESH_DEDUP_MODEL_S", 60.0)}
        # Bounded state: most keys any one table holds.
        self.max_keys = env_int("CIVICMESH_LIMITER_MAX_KEYS", 50000)
        self.max_connections = env_int("CIVICMESH_MAX_CONNECTIONS", 256)
        self.telemetry_interval_s = env_float("CIVICMESH_SECURITY_LOG_S", 60.0)


class BudgetConfig:
    def __init__(self):
        # Model calls (every litellm attempt: fallbacks, retries, parallel
        # translation segments). Exhausted -> optional calls fail closed.
        self.per_minute = env_int("CIVICMESH_LLM_MAX_PER_MIN", 30)
        self.per_hour = env_int("CIVICMESH_LLM_MAX_PER_HOUR", 600)
        self.per_day = env_int("CIVICMESH_LLM_MAX_PER_DAY", 4000)
        self.tokens_per_day = env_int("CIVICMESH_LLM_MAX_TOKENS_PER_DAY", 2_000_000)
        self.max_request_tokens = env_int("CIVICMESH_LLM_MAX_REQUEST_TOKENS", 8000)
        self.concurrent = env_int("CIVICMESH_LLM_MAX_CONCURRENT", 4)
        self.wait_s = env_float("CIVICMESH_LLM_WAIT_S", 2.0)
        self.breaker_failures = env_int("CIVICMESH_LLM_BREAKER_FAILURES", 5)
        self.breaker_cooldown_s = env_float("CIVICMESH_LLM_BREAKER_COOLDOWN_S", 60.0)
        self.breaker_max_cooldown_s = env_float("CIVICMESH_LLM_BREAKER_MAX_COOLDOWN_S", 900.0)
        self.disabled = env_str("CIVICMESH_LLM_DISABLED", "0") == "1"
