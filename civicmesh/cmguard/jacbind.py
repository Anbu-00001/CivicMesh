"""Make jac-scale listen on loopback only, behind the gateway.

jac-scale 0.2.17 starts uvicorn with `run_server(port=...)` and never passes
the host, so it binds 0.0.0.0 whatever jac.toml or `--host` say. On Hugging
Face only the app port is routed from the Internet, but the gateway must be
the only way in, so when cmguard/serve.py sets CIVICMESH_UPSTREAM_BIND the
server's run_server gets that host. Without the variable nothing changes.

The same variable turns off jac-scale's access log. Its run_server configures
uvicorn with an INFO access logger and no way to opt out, so every request
would print a line with its path and status even though the gateway's own log
is off. A filter on the logger stays in place through uvicorn's logging setup.
"""

import logging
import os


def _drop_access_record(_record: logging.LogRecord) -> bool:
    return False


def silence_access_log() -> None:
    logging.getLogger("uvicorn.access").addFilter(_drop_access_record)


def bind_upstream() -> str:
    host = os.environ.get("CIVICMESH_UPSTREAM_BIND", "").strip()
    if not host:
        return ""
    silence_access_log()
    try:
        from jac_scale.jserver.jfast_api import JFastApiServer
    except Exception:
        return ""
    run = JFastApiServer.run_server
    if getattr(run, "_civicmesh_bind", False):
        return host

    def run_server(self, *args, **kwargs):
        kwargs["host"] = host
        return run(self, *args, **kwargs)

    run_server._civicmesh_bind = True
    JFastApiServer.run_server = run_server
    return host
