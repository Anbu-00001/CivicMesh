"""Security telemetry: aggregate counters only.

Counts rejected requests by reason and route class, model-budget denials and
circuit-breaker trips. No address, visitor id, token or message text is ever
recorded. A summary line goes to the log at most once per interval, and only
when something changed.
"""

import json
import os
import sys
import threading
import time
from collections import Counter

DEFAULT_INTERVAL_S = float(os.environ.get("CIVICMESH_SECURITY_LOG_S", "") or 60)

_COUNTS = Counter()
_LOCK = threading.Lock()
_LAST = {"t": time.monotonic(), "snapshot": {}}


def count(event: str, n: int = 1) -> None:
    with _LOCK:
        _COUNTS[event] += n


def snapshot() -> dict:
    with _LOCK:
        return dict(_COUNTS)


def maybe_log(interval_s: "float | None" = None, source: str = "app") -> None:
    """Print one aggregate line if counters moved since the last one."""
    interval_s = DEFAULT_INTERVAL_S if interval_s is None else interval_s
    now = time.monotonic()
    if now - _LAST["t"] < interval_s:
        return
    snap = snapshot()
    delta = {k: v - _LAST["snapshot"].get(k, 0) for k, v in snap.items() if v != _LAST["snapshot"].get(k, 0)}
    _LAST["t"] = now
    _LAST["snapshot"] = snap
    if delta:
        line = {"event": "civicmesh_security", "source": source, "window_s": int(interval_s), "counts": delta}
        print(json.dumps(line, sort_keys=True), file=sys.stdout, flush=True)
