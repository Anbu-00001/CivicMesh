"""PlatformWalker — live numbers for the landing page, nothing invented.

Runs the real deterministic engine on the landing page's example prompt
(read-only: no NeedNode, no edges, no applications are written) and returns
the parsed facts, the top matches with their tiers and SNAP estimate, the
follow-up question and the measured engine time, plus the platform counters
from engine/stats.jac and catalog / language / policy provenance.
"""

import json;
import os;
import time;
import from engine.parse { parse_intake }
import from engine.score { rank_resources, question_for }
import from engine.stats { stats_snapshot }
import from engine.i18n { routed_languages, language_catalog }
import from engine.messages { message_languages }
import from engine.policy { policy_sources, POLICY_VERSION }

glob PREVIEW_PROMPT: str = "I'm a single mom with 2 kids in Houston. I earn $1,800 a month and we need food.";
glob CATALOG: list = [];

"""Catalog from data/resources.json (the same file SeedWalker loads)."""
def load_catalog -> list {
    if CATALOG {
        return CATALOG;
    }
    for c in [os.path.join(os.getcwd(), "data", "resources.json"), os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "resources.json")] {
        if os.path.exists(c) {
            data = json.load(open(c, encoding="utf-8"))["resources"];
            for r in data {
                CATALOG.append({"resource": r, "rule": r["eligibility"], "form": r["form"]});
            }
            break;
        }
    }
    return CATALOG;
}

walker PlatformWalker {
    has summary: dict = {};

    can run with `Root entry {
        items = load_catalog();
        t0 = time.perf_counter();
        p = parse_intake(PREVIEW_PROMPT);
        rk = rank_resources(items, p, PREVIEW_PROMPT, 3, "en");
        ms = round((time.perf_counter() - t0) * 1000.0, 2);
        top: list = [];
        for s in rk["ranked"][:3] {
            top.append({
                "name": str(s["resource_name"]), "tier": str(s["tier"]),
                "p": float(s["p_eligible"]), "benefit": str(dict(s.get("benefit", {}) or {}).get("label", ""))
            });
        }
        self.summary = {
            "preview": {
                "prompt": PREVIEW_PROMPT, "engine_ms": ms,
                "language": p["language"], "category": p["category"], "household": p["household_size"],
                "income_annual": p["income_annual"], "city": p["city"], "state": p["state"],
                "top": top, "question": question_for(str(rk["ask"]["key"]), "en"), "affects": int(rk["ask"]["affects"]),
                "scored": int(rk["all_count"])
            },
            "stats": stats_snapshot(),
            "programs": len(items),
            "languages_routed": len(routed_languages()),
            "languages_native": len(message_languages()),
            "languages": language_catalog(),
            "policy_version": POLICY_VERSION,
            "policy_sources": policy_sources()
        };
        report self.summary;
    }
}

sem PlatformWalker is "Read-only: runs the engine on the landing page's example prompt and returns live platform counters and provenance.";
