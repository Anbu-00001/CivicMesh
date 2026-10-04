"""A fake OpenAI-compatible model provider for the security tests (stdlib).

    python3 civicmesh/tests/fake_llm.py 8799

Answers POST /v1/chat/completions like a model would (structured output for
narration, the source text back for translation), and records every request:
GET /__stats returns {"requests", "max_concurrent", "auth_headers_seen", "by_model"};
a model whose name contains "retired" answers 410 Gone, as NVIDIA's API did
for a retired model;
POST /__reset clears it. The container is pointed here with
NVIDIA_NIM_API_BASE / OPENAI_API_BASE, so the tests can count exactly how
many model calls the app made and prove the budget bounds them.
"""

import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = {"requests": 0, "inflight": 0, "max_concurrent": 0, "auth": set(), "by_model": {}}
LOCK = threading.Lock()
DELAY_S = float(sys.argv[2]) if len(sys.argv) > 2 else 0.3


def reply_for(body: dict) -> dict:
    messages = body.get("messages") or []
    last = str(messages[-1].get("content", "")) if messages else ""
    wants_json = bool(body.get("response_format")) or "json" in json.dumps(body.get("tools", "")).lower()
    content = json.dumps({"message": "Here is what I found for you, and the next step to take.", "chips": []}) if wants_json else last[-2000:]
    msg = {"role": "assistant", "content": content}
    if body.get("tools"):
        fn = body["tools"][0].get("function", {}).get("name", "respond")
        msg = {"role": "assistant", "content": None, "tool_calls": [{"id": "call_1", "type": "function", "function": {"name": fn, "arguments": content}}]}
    return {"id": "fake", "object": "chat.completion", "created": int(time.time()), "model": body.get("model", "fake"),
            "choices": [{"index": 0, "message": msg, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 50, "completion_tokens": 20, "total_tokens": 70}}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # noqa: A002 (quiet)
        pass

    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/__stats":
            with LOCK:
                self._json(200, {"requests": STATE["requests"], "max_concurrent": STATE["max_concurrent"],
                                 "auth_headers_seen": sorted(STATE["auth"]), "by_model": dict(STATE["by_model"])})
        else:
            self._json(404, {})

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        if self.path == "/__reset":
            with LOCK:
                STATE.update(requests=0, max_concurrent=0, auth=set(), by_model={})
            self._json(200, {"ok": True})
            return
        with LOCK:
            STATE["requests"] += 1
            STATE["inflight"] += 1
            STATE["max_concurrent"] = max(STATE["max_concurrent"], STATE["inflight"])
            STATE["auth"].add(str(self.headers.get("authorization", ""))[:40])
        try:
            time.sleep(DELAY_S)
            try:
                body = json.loads(raw or b"{}")
            except Exception:
                body = {}
            model = str(body.get("model", ""))
            with LOCK:
                STATE["by_model"][model] = STATE["by_model"].get(model, 0) + 1
            if "retired" in model:
                self._json(410, {"type": "about:blank", "title": "Gone", "status": 410, "detail": f"Model {model} has been retired."})
            else:
                self._json(200, reply_for(body))
        finally:
            with LOCK:
                STATE["inflight"] -= 1


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
