"""Make jac-scale listen on loopback only, behind the gateway.

jac-scale 0.2.17 starts uvicorn with `run_server(port=...)` and never passes
the host, so it binds 0.0.0.0 whatever jac.toml or `--host` say. On Hugging
Face only the app port is routed from the Internet, but the gateway must be
the only way in, so when cmguard/serve.py sets CIVICMESH_UPSTREAM_BIND the
server's run_server gets that host. Without the variable nothing changes.
"""

import os


def bind_upstream() -> str:
    host = os.environ.get("CIVICMESH_UPSTREAM_BIND", "").strip()
    if not host:
        return ""
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
