"""Platform-wide live counters, in process, since the server last started.

Every visitor has a private graph (their own root), so no walker can see
other visitors' nodes. These counters are the one shared, anonymous view:
turns served, languages seen, need mix, engine latency percentiles, how many
turns needed an LLM on the critical path, and narration success/latency.
Visitor ids are stored only as a truncated SHA-256. Resets on restart —
the UI says "since last restart".
"""

import datetime;
import hashlib;

glob STATS: dict = {
    "started": datetime.datetime.utcnow().isoformat() + "Z",
    "turns": 0, "visitors": {}, "languages": {}, "categories": {},
    "engine_ms": [], "sync_llm": 0, "deadline_hits": 0,
    "narr_ok": 0, "narr_fail": 0, "narr_ms": []
};
glob WINDOW: int = 500;

"""Nearest-rank percentile of a list (0 when empty)."""
def _pct(xs: list, q: float) -> float {
    if not xs { return 0.0; }
    s = sorted(xs);
    return float(s[max(0, min(len(s) - 1, int(round(q * (len(s) - 1)))))]);
}

"""Count one chat turn."""
def record_turn(user_id: str, language: str, category: str, engine_ms: float, sync_llm: bool, deadline_hit: bool) -> None {
    STATS["turns"] = int(STATS["turns"]) + 1;
    STATS["visitors"][hashlib.sha256(str(user_id).encode()).hexdigest()[:12]] = 1;
    lang = str(language or "?");
    STATS["languages"][lang] = int(STATS["languages"].get(lang, 0)) + 1;
    cat = str(category or "?");
    STATS["categories"][cat] = int(STATS["categories"].get(cat, 0)) + 1;
    STATS["engine_ms"].append(float(engine_ms));
    if len(STATS["engine_ms"]) > WINDOW { STATS["engine_ms"] = STATS["engine_ms"][-WINDOW:]; }
    if sync_llm { STATS["sync_llm"] = int(STATS["sync_llm"]) + 1; }
    if deadline_hit { STATS["deadline_hits"] = int(STATS["deadline_hits"]) + 1; }
}

"""Count one background narration."""
def record_narration(ok: bool, ms: float) -> None {
    if ok {
        STATS["narr_ok"] = int(STATS["narr_ok"]) + 1;
        STATS["narr_ms"].append(float(ms));
        if len(STATS["narr_ms"]) > WINDOW { STATS["narr_ms"] = STATS["narr_ms"][-WINDOW:]; }
    } else {
        STATS["narr_fail"] = int(STATS["narr_fail"]) + 1;
    }
}

"""JSON-safe snapshot for the Impact tab and the landing page."""
def stats_snapshot -> dict {
    turns = int(STATS["turns"]);
    narr_n = int(STATS["narr_ok"]) + int(STATS["narr_fail"]);
    langs = sorted([[k, v] for (k, v) in STATS["languages"].items()], key=lambda kv: list : -int(kv[1]));
    cats = sorted([[k, v] for (k, v) in STATS["categories"].items()], key=lambda kv: list : -int(kv[1]));
    return {
        "since": str(STATS["started"]),
        "turns": turns,
        "visitors": len(STATS["visitors"]),
        "languages": [{"lang": str(l[0]), "count": int(l[1])} for l in langs],
        "categories": [{"category": str(c[0]), "count": int(c[1])} for c in cats],
        "engine_ms_p50": round(_pct(STATS["engine_ms"], 0.5), 1),
        "engine_ms_p95": round(_pct(STATS["engine_ms"], 0.95), 1),
        "zero_llm_share": round(1.0 - int(STATS["sync_llm"]) / turns, 3) if turns else 1.0,
        "sync_llm_turns": int(STATS["sync_llm"]),
        "deadline_hits": int(STATS["deadline_hits"]),
        "narrations": narr_n,
        "narration_ok_share": round(int(STATS["narr_ok"]) / narr_n, 3) if narr_n else 0.0,
        "narration_ms_p50": round(_pct(STATS["narr_ms"], 0.5), 0)
    };
}
