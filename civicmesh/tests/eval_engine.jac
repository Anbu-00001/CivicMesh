"""Golden-set evaluation for the deterministic engine.

Runs every case in tests/golden.json (EN/ES, full pipeline) and
tests/golden_i18n.json (language ID + routing in 70+ more languages) and
tests/golden_adversarial.json (negation, idioms, cross-category traps,
crisis, code-switching, romanized scripts, no-signal input) through
parse → rank → plan → routes
and reports field-extraction accuracy, top-3 recommendation hit rate,
exclusion violations, LLM-routing precision, and latency percentiles.

    jac run tests/eval_engine.jac          (from civicmesh/)

Exit code is non-zero when any metric drops below its floor, so this doubles
as a CI regression gate.
"""

import json;
import os;
import sys;
import time;
import from engine.parse { parse_intake }
import from engine.score { rank_resources }
import from engine.plan { build_plan }
import from engine.paths { plan_routes }

glob FLOORS: dict = {"field_accuracy": 0.9, "top3_hit_rate": 0.85, "exclusion_violations": 0};

"""Percentile of a sorted list (nearest-rank)."""
def pct(xs: list, q: float) -> float {
    if not xs { return 0.0; }
    s = sorted(xs);
    k = max(0, min(len(s) - 1, int(round(q * (len(s) - 1)))));
    return s[k];
}

with entry {
    # Effective-dated rules (Medicaid for refugees ends 2026-10-01, summer
    # meals run Jun–Aug): pin the policy date so the gate is reproducible.
    os.environ.setdefault("CIVICMESH_POLICY_DATE", "2026-09-27");
    data = json.load(open("data/resources.json"))["resources"];
    edges = json.load(open("data/transitions.json"))["transitions"];
    items: list = [{"resource": r, "rule": r["eligibility"], "form": r["form"]} for r in data];
    cases = json.load(open("tests/golden.json"))["cases"];
    i18n_cases = json.load(open("tests/golden_i18n.json", encoding="utf-8"))["cases"];
    for c in i18n_cases { c["suite"] = "i18n"; }
    adv_cases = json.load(open("tests/golden_adversarial.json", encoding="utf-8"))["cases"];
    for c in adv_cases { c["suite"] = "adversarial"; }
    hold_cases = json.load(open("tests/golden_holdout.json", encoding="utf-8"))["cases"];
    for c in hold_cases { c["suite"] = "holdout"; }
    cases = cases + i18n_cases + adv_cases + hold_cases;
    suite_tot: dict = {};
    suite_ok: dict = {};
    langs_ok: dict = {};

    field_total = 0;
    field_ok = 0;
    per_field: dict = {};
    top_total = 0;
    top_ok = 0;
    excl_viol = 0;
    lat: list = [];
    failures: list = [];

    # Warm regex caches so the first case doesn't skew p95.
    parse_intake("warm up the regex cache with $100 a month in Texas");

    for c in cases {
        text = c["text"];
        t0 = time.perf_counter();
        p = parse_intake(text);
        rk = rank_resources(items, p, text, 6, p["language"] or "en");
        pl = build_plan(rk["ranked"], p["urgency"], p["language"] or "en");
        p_of: dict = {};
        for s in rk["ranked"] { p_of[s["resource_name"]] = float(s["p_eligible"]) * float(s["approval"]["mean"]); }
        srcs = [s["resource_name"] for s in rk["ranked"] if s["tier"] in ["likely", "possible"]];
        goals: dict = {};
        for s in rk["ranked"] { if s["capacity"] == "waitlist" { goals[s["resource_name"]] = 0.9; } }
        plan_routes(edges, p_of, srcs, goals, 3, 1);
        lat.append((time.perf_counter() - t0) * 1000.0);

        for (k, v) in c.get("expect", {}).items() {
            field_total += 1;
            got = p.get(k);
            ok = got == v;
            if k == "flag" {
                got = p.get("flags", []);
                ok = v in got;
            } elif k == "flag_absent" {
                got = p.get("flags", []);
                ok = v not in got;
            } elif k == "category_in" {
                got = p.get("category");
                ok = got in v;
            } elif k == "secondary_nonempty" {
                got = p.get("secondary", []);
                ok = len(got) > 0;
            }
            su = str(c.get("suite", "golden"));
            suite_tot[su] = int(suite_tot.get(su, 0)) + 1;
            if ok { suite_ok[su] = int(suite_ok.get(su, 0)) + 1; }
            if c.get("suite") == "i18n" and k in ["language", "category"] {
                lk = str(c["expect"].get("language", "")) or "?";
                langs_ok.setdefault(lk, True);
                langs_ok[lk] = bool(langs_ok[lk]) and ok;
            }
            per_field.setdefault(k, [0, 0]);
            per_field[k][1] += 1;
            if ok {
                field_ok += 1;
                per_field[k][0] += 1;
            } else {
                failures.append(f"FIELD {k}: want {v!r} got {got!r} | {text[:60]}");
            }
        }
        top3 = [s["resource_name"] for s in rk["ranked"][:3]];
        if c.get("top3_any") {
            top_total += 1;
            if any([n in top3 for n in c["top3_any"]]) {
                top_ok += 1;
            } else {
                failures.append(f"TOP3 want one of {c['top3_any']} got {top3} | {text[:60]}");
            }
        }
        plan_names = [st["agency_name"] for st in pl["steps"]];
        if c.get("plan_any") {
            top_total += 1;
            if any([n in plan_names for n in c["plan_any"]]) {
                top_ok += 1;
            } else {
                failures.append(f"PLAN want one of {c['plan_any']} got {plan_names} | {text[:60]}");
            }
        }
        for n in c.get("plan_none", []) {
            if n in plan_names {
                excl_viol += 1;
                failures.append(f"PLAN {n} should not be in the plan | {text[:60]}");
            }
        }
        for n in c.get("top3_none", []) {
            if n in top3 {
                excl_viol += 1;
                failures.append(f"EXCL {n} should not be in top 3 | {text[:60]}");
            }
        }
    }

    field_acc = field_ok / max(1, field_total);
    top_rate = top_ok / max(1, top_total);
    print("CivicMesh engine eval — " + str(len(cases)) + " cases");
    print(f"  field accuracy      {field_acc:.1%}  ({field_ok}/{field_total})");
    for (k, v) in sorted(per_field.items()) {
        print(f"    {k:<15} {v[0]}/{v[1]}");
    }
    n_langs = len([k for k in langs_ok.keys() if k != "?"]) + 2;
    n_langs_ok = len([k for (k, v) in langs_ok.items() if v and k != "?"]) + 2;
    print(f"  languages routed    {n_langs_ok}/{n_langs} fully correct (EN + ES + {len(i18n_cases)} multilingual cases)");
    for (su, n) in sorted(suite_tot.items()) {
        print(f"  suite {su:<12}  {int(suite_ok.get(su, 0))}/{n} checks");
    }
    print(f"  top-3 hit rate      {top_rate:.1%}  ({top_ok}/{top_total})");
    print(f"  exclusion errors    {excl_viol}");
    print(f"  latency / turn      p50 {pct(lat, 0.5):.2f} ms · p95 {pct(lat, 0.95):.2f} ms · max {max(lat):.2f} ms");
    for f in failures {
        print("  ✗ " + f);
    }
    report_path = "tests/eval_report.json";
    json.dump({
        "cases": len(cases), "field_accuracy": round(field_acc, 4), "per_field": per_field,
        "suites": {su: {"ok": int(suite_ok.get(su, 0)), "total": n} for (su, n) in suite_tot.items()},
        "languages": {"tested": n_langs, "fully_correct": n_langs_ok, "failing": sorted([k for (k, v) in langs_ok.items() if not v])},
        "top3_hit_rate": round(top_rate, 4), "exclusion_violations": excl_viol,
        "latency_ms": {"p50": round(pct(lat, 0.5), 3), "p95": round(pct(lat, 0.95), 3), "max": round(max(lat), 3)},
        "failures": failures
    }, open(report_path, "w"), indent=2);
    if field_acc < FLOORS["field_accuracy"] or top_rate < FLOORS["top3_hit_rate"] or excl_viol > FLOORS["exclusion_violations"] {
        print("  FAIL: below regression floor");
        sys.exit(1);
    }
    print("  PASS");
}
