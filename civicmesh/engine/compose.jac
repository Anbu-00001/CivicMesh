"""Turn assembly helpers: multi-turn profile memory, reply text, tracing.

* merge_profiles — the user answers the agent's follow-up question ("about
  $1,500 a month") and that single fact is folded into the profile carried
  over from the previous turn instead of starting from scratch.
* compose_reply — the deterministic reply in English or Spanish, built from
  engine output, so a useful answer never waits on an LLM.
* Tracer spans — OpenTelemetry-shaped spans (trace_id / span_id / parent,
  start/end in unix nanos, `gen_ai.*` attributes on LLM spans) so each turn
  renders as a latency waterfall and can be exported as-is.
"""

import re;
import time;
import uuid;

glob MERGE_FIELDS: list = ["income_annual", "household_size", "age", "state", "city", "zip", "citizenship"];

# Yes/no follow-up answers map to canonical evidence phrases so the same
# situation matcher that reads free text can read the answer.
glob ANSWER_EVIDENCE: dict = {
    "homeless": "homeless", "veteran": "veteran", "disability": "disabled",
    "dv": "domestic violence", "young_child": "baby", "children": "children",
    "eviction": "eviction notice"
};
glob NEGATIVE_QUESTIONS: list = ["homeless", "dv"];
glob YES_RE: str = "^\\s*(?:yes|yeah|yep|yup|sure|correct|right|i am|i do|i have|we do|we are|s[ií]|claro|as[ií] es|tengo|soy)\\b";
glob NO_RE: str = "^\\s*(?:no|nope|nah|not really|i'?m not|i don'?t|we don'?t|none|ninguno|no tengo|no soy)\\b";

"""Fold a new parse into the case carried over from earlier turns.

Same case → new evidence wins and unknown fields keep their earlier value; a
bare answer ("about $1,500 a month", "yes") inherits the earlier need instead
of forcing an LLM call. A different language or a clearly different need
starts a fresh case, so a demo visitor trying several prompts in a row never
sees one person's facts leak into another's.
"""
def merge_profiles(prior: dict, cur: dict, text: str = "", answering: str = "") -> dict {
    out = dict(cur);
    out["answered"] = [];
    out["case_text"] = str(text)[-1500:];
    if not prior {
        return out;
    }
    short = len(str(text).split()) < 4;
    if short and prior.get("language") {
        # "no", "sí", "$900" carry too little signal to switch language.
        out["language"] = prior.get("language");
    }
    # Length, not "is a question pending", decides: the client marks every
    # typed message as a possible answer, but a full sentence about a new
    # need in a new language is a new case.
    lang_changed = (not short) and bool(cur.get("language")) and bool(prior.get("language")) and cur.get("language") != prior.get("language");
    topic_changed = (not short) and bool(cur.get("category")) and bool(prior.get("category")) and cur.get("category") != prior.get("category") and float(cur.get("category_conf", 0)) >= 0.45;
    if lang_changed or topic_changed {
        out["new_case"] = True;
        return out;
    }
    out["case_text"] = (str(prior.get("case_text", "")) + " \n " + str(text))[-1500:];
    answered = list(prior.get("answered", []));
    if answering {
        if answering not in answered { answered.append(answering); }
        low = str(text).lower();
        # "Do you have a safe place to sleep tonight?" / "Are you safe at home?"
        # are asked in the negative: a "no" is the evidence.
        affirm = re.search(NO_RE, low) if answering in NEGATIVE_QUESTIONS else re.search(YES_RE, low);
        if answering in ANSWER_EVIDENCE and affirm {
            out["case_text"] = out["case_text"] + " " + ANSWER_EVIDENCE[answering];
            out["answered_yes"] = answering;
        }
    }
    out["answered"] = answered;
    for k in MERGE_FIELDS {
        v = cur.get(k);
        unknown = (v is None) or (v == "") or (k == "income_annual" and int(v) < 0) or (k in ["household_size", "age"] and int(v) == 0);
        if unknown and prior.get(k) not in [None, ""] {
            out[k] = prior.get(k);
        }
    }
    if not cur.get("category") and prior.get("category") {
        out["category"] = prior.get("category");
        out["secondary"] = list(prior.get("secondary", []));
        out["category_conf"] = float(prior.get("category_conf", 0.5));
        out["needs_llm"] = False;
        out["llm_reason"] = "";
        out["carried_category"] = True;
    }
    if not cur.get("language") and prior.get("language") {
        out["language"] = prior.get("language");
        if out.get("llm_reason", "") == "language outside EN/ES" {
            out["needs_llm"] = False;
            out["llm_reason"] = "";
        }
    }
    flags = list(cur.get("flags", []));
    for f in list(prior.get("flags", [])) {
        if f not in flags { flags.append(f); }
    }
    out["flags"] = flags;
    if prior.get("urgency") == "immediate" { out["urgency"] = "immediate"; }
    known = 0;
    if int(out.get("income_annual", -1)) >= 0 { known += 1; }
    if int(out.get("household_size", 0)) > 0 { known += 1; }
    if int(out.get("age", 0)) > 0 { known += 1; }
    if out.get("state") or out.get("zip") { known += 1; }
    if out.get("citizenship") { known += 1; }
    out["completeness"] = round(known / 5.0, 2);
    return out;
}

"""Deterministic reply text (EN/ES). Real newlines; **bold** is rendered by the UI."""
def compose_reply(lang: str, profile: dict, ranking: dict, plan: dict, routes: list, question: str) -> str {
    es = lang == "es";
    ranked = list(ranking.get("ranked", []));
    likely = [s for s in ranked if s["tier"] == "likely"];
    maybe = [s for s in ranked if s["tier"] in ["possible", "needs_info"]];
    steps = list(plan.get("steps", []));
    pinned = [s for s in ranked if s.get("pinned", False)];
    lines: list = [];

    if pinned {
        p = pinned[0];
        lines.append(("**Primero, su seguridad:** " if es else "**First, your safety:** ") + p["resource_name"] + " — " + p["contact_phone"] + (" (24/7, gratis y confidencial)." if es else " (24/7, free and confidential)."));
    }
    if likely {
        n = len(likely);
        if es {
            lines.append("Encontré **" + str(n) + " programa" + ("s" if n != 1 else "") + "** para los que probablemente califica" + ((" y " + str(len(maybe)) + " más que podrían funcionar.") if maybe else "."));
        } else {
            lines.append("I found **" + str(n) + " program" + ("s" if n != 1 else "") + "** you likely qualify for" + ((" and " + str(len(maybe)) + " more that could work.") if maybe else "."));
        }
    } elif maybe {
        if es {
            lines.append("Aún no hay una coincidencia segura, pero **" + str(len(maybe)) + " programas** podrían funcionar cuando sepa un poco más.");
        } else {
            lines.append("Nothing is a sure match yet, but **" + str(len(maybe)) + " programs** could work once I know a bit more.");
        }
    } else {
        lines.append("Todavía no encuentro un programa que encaje directamente." if es else "I couldn't find a direct match yet.");
    }
    if steps {
        s0 = steps[0];
        lines.append(("**Empiece aquí:** " if es else "**Start here:** ") + s0["agency_name"] + " — " + s0["action_description"] + ".");
    }
    if routes {
        r = routes[0];
        if es {
            lines.append("**Ruta a largo plazo:** " + r["start"] + " → " + r["end"] + " en ~" + str(r["total_days"]) + " días.");
        } else {
            lines.append("**Longer-term route:** " + r["start"] + " → " + r["end"] + " in about " + str(r["total_days"]) + " days.");
        }
    }
    if question {
        lines.append(("**Una pregunta para afinar esto:** " if es else "**One question to sharpen this:** ") + question);
    }
    return "\n\n".join(lines);
}

"""New trace context."""
def new_trace() -> dict {
    return {"trace_id": uuid.uuid4().hex, "t0": time.perf_counter(), "t0_ns": time.time_ns(), "spans": []};
}

"""Open a span; returns the span record (close it with span_end)."""
def span_begin(tr: dict, name: str, kind: str = "INTERNAL", parent: str = "", attrs: dict = {}) -> dict {
    now = time.perf_counter();
    sp = {
        "trace_id": tr["trace_id"],
        "span_id": uuid.uuid4().hex[:16],
        "parent_span_id": parent,
        "name": name,
        "kind": kind,
        "start_ms": round((now - tr["t0"]) * 1000.0, 3),
        "start_time_unix_nano": int(tr["t0_ns"] + (now - tr["t0"]) * 1e9),
        "attributes": dict(attrs),
        "status": "OK",
        "_p0": now
    };
    return sp;
}

"""Close a span and append it to the trace."""
def span_end(tr: dict, sp: dict, attrs: dict = {}, status: str = "OK") -> dict {
    now = time.perf_counter();
    sp["duration_ms"] = round((now - sp["_p0"]) * 1000.0, 3);
    sp["end_time_unix_nano"] = int(sp["start_time_unix_nano"] + (now - sp["_p0"]) * 1e9);
    for (k, v) in attrs.items() {
        sp["attributes"][k] = v;
    }
    sp["status"] = status;
    sp.pop("_p0", None);
    tr["spans"].append(sp);
    return sp;
}

"""Spans in start order, JSON-safe."""
def export_spans(tr: dict) -> list {
    return sorted(list(tr["spans"]), key=lambda s: dict : float(s["start_ms"]));
}
