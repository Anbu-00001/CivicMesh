"""Container entry point: `python -m cmguard.serve` (from civicmesh/).

1. Secrets. jac-scale signs login tokens with jac.toml's [plugins.scale.jwt]
   secret; its built-in default is a public string, so a token for any
   visitor could be forged from the source code. The secret now comes from
   CIVICMESH_JWT_SECRET, generated here per boot when unset (tokens then end
   at a restart, like the rest of a free Space's state). The same is done for
   CIVICMESH_SIGNING_KEY (narration/translation tokens) and the jac-scale
   system account password. A configured secret shorter than 32 characters, or
   equal to the public default, stops the boot.
2. jac-scale runs as a child process on 127.0.0.1 only.
3. The gateway (cmguard/gateway.py) is the only public listener, and it opens
   only once jac-scale answers, so the host keeps its "Starting" screen up
   during the boot. If jac-scale exits, this process exits too, so the host
   restarts the container.
"""

import os
import secrets
import signal
import subprocess
import sys
import threading

PUBLIC_DEFAULT_JWT = "supersecretkey_for_testing_only!"


def ensure_secret(name: str, generated_bytes: int = 48) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        value = secrets.token_urlsafe(generated_bytes)
    if len(value) < 32 or value == PUBLIC_DEFAULT_JWT:
        sys.exit(f"{name} must be at least 32 random characters (unset it to generate one per boot)")
    os.environ[name] = value
    return value


def wait_until_ready(url: str, child, timeout_s: float) -> None:
    import time
    import urllib.request

    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if child.poll() is not None:
            sys.exit(f"jac-scale exited with code {child.returncode} before it was ready")
        try:
            with urllib.request.urlopen(url, timeout=3) as r:
                if r.status < 500:
                    return
        except Exception:
            pass
        time.sleep(0.5)
    sys.exit(f"jac-scale wasn't ready after {timeout_s:.0f} s")


def main() -> None:
    port = int(os.environ.get("PORT", "7860") or 7860)
    upstream_port = int(os.environ.get("CIVICMESH_UPSTREAM_PORT", "8000") or 8000)
    ensure_secret("CIVICMESH_JWT_SECRET")
    ensure_secret("CIVICMESH_SIGNING_KEY")
    os.environ["SYSTEM_USER_PASSWORD"] = os.environ.get("SYSTEM_USER_PASSWORD", "").strip() or secrets.token_urlsafe(24)
    os.environ["CIVICMESH_UPSTREAM"] = f"http://127.0.0.1:{upstream_port}"
    os.environ["CIVICMESH_UPSTREAM_BIND"] = "127.0.0.1"

    child = subprocess.Popen(
        ["jac", "start", "app.jac", "--no-dev", "--port", str(upstream_port), "--host", "127.0.0.1"],
        env=dict(os.environ),
    )

    def forward(signum, _frame):
        try:
            child.send_signal(signum)
        finally:
            sys.exit(0)

    signal.signal(signal.SIGTERM, forward)
    signal.signal(signal.SIGINT, forward)

    def watch():
        code = child.wait()
        print(f"jac-scale exited with code {code}; stopping", file=sys.stderr, flush=True)
        os._exit(code or 1)

    threading.Thread(target=watch, daemon=True).start()

    # Open the public port only once jac-scale answers. Until then the host
    # shows its own "Starting" screen (Hugging Face waits for the app port), so
    # no visitor gets a page whose first requests fail while the engine boots.
    wait_until_ready(f"http://127.0.0.1:{upstream_port}/healthz", child,
                     float(os.environ.get("CIVICMESH_BOOT_TIMEOUT_S", "") or 900))

    import uvicorn

    from cmguard.config import GatewayConfig
    from cmguard.gateway import app

    cfg = GatewayConfig()
    uvicorn.run(
        app, host="0.0.0.0", port=port,
        access_log=False,           # no client addresses or paths in the logs
        log_level="warning",
        proxy_headers=False,        # client address handled by cmguard.clientip
        server_header=False,
        date_header=False,
        limit_concurrency=cfg.max_connections,
        timeout_keep_alive=5,
        h11_max_incomplete_event_size=16 * 1024,
    )


if __name__ == "__main__":
    main()
