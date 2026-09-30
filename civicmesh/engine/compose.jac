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
import from engine.i18n { yes_no, unspaced_chars, ascii_digits }
import from engine.facts_i18n { zh_number }
import from engine.messages { msg, has_messages }

glob MERGE_FIELDS: list = ["income_annual", "household_size", "age", "state", "city", "zip", "citizenship"];

# Yes/no follow-up answers map to canonical evidence phrases so the same
# situation matcher that reads free text can read the answer.
glob ANSWER_EVIDENCE: dict = {
    "homeless": "homeless", "veteran": "veteran", "disability": "disabled",
    "dv": "domestic violence", "young_child": "baby", "children": "children",
    "eviction": "eviction notice"
};
glob NEGATIVE_QUESTIONS: list = ["homeless", "dv"];
# The flag a "yes" (or, for the negative questions, a "no") sets. Appending the
# evidence word to the case text alone left the flag unset, so "Yes" to "Do you
# or someone in your household have a disability?" changed nothing.
glob ANSWER_FLAGS: dict = {"homeless": "homeless", "veteran": "veteran", "disability": "disabled", "dv": "dv", "children": "children"};
glob COUNT_WORDS: dict = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                          "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10};
glob YES_RE: str = "^\\s*(?:yes|yeah|yep|yup|sure|correct|right|i am|i do|i have|we do|we are|s[ií]|claro|as[ií] es|tengo|soy)\\b";
glob NO_RE: str = "^\\s*(?:no|nope|nah|not really|i'?m not|i don'?t|we don'?t|none|ninguno|no tengo|no soy)\\b";
# Words a bare income answer may carry besides the number: hedges, currency
# and pay periods ("about $2,000 a month", "unos 1500 al mes", "大概两千块").
glob ANSWER_FILLER: str = "\\b(?:about|around|approximately|approx|roughly|maybe|almost|nearly|just|only|like|over|under|per|a|an|each|every|i|we|make|earn|get|it'?s|is|months?|monthly|mo|years?|yearly|annual|annually|weeks?|weekly|hours?|hourly|hrs?|dollars?|usd|bucks|k|cerca|de|unos|unas|como|m[aá]s|o|menos|aproximadamente|al|por|mes|mensual|a[nñ]o|semana|hora|d[oó]lares|gano|ganamos|ganho|m[eê]s|reais)\\b|大概|大约|大約|左右|差不多|美元|美金|块钱|塊錢|块|塊|元|每个月|每個月|每月|一个月|一個月|月|每年|年|每小时|每小時|小时|小時|每周|每週|周|週|星期";

"""Fold a new parse into the case carried over from earlier turns.

One conversation is one person. New evidence wins, unknown fields keep their
earlier value, and flags accumulate: violence disclosed in Chinese still
counts after a switch to English. The latest message sets the need and, when
it says enough, the reply language, because people switch languages mid-
conversation and a second need ("also, the rent") is the same household's.
A bare answer ("about $1,500 a month", "yes", "2000") inherits the earlier
need instead of forcing an LLM call. Starting over is explicit: the New case
button sends no prior.
"""
def merge_profiles(prior: dict, cur: dict, text: str = "", answering: str = "") -> dict {
    out = dict(cur);
    out["answered"] = [];
    out["case_text"] = str(text)[-1500:];
    if not prior {
        return out;
    }
    # Chinese / Japanese / Thai sentences have no spaces: count characters.
    short = len(str(text).split()) < 4 and unspaced_chars(str(text)) < 6;
    if short and prior.get("language") and float(cur.get("language_conf", 0) or 0) < 0.85 {
        # "no", "sí", "$900" carry too little signal to switch language; a
        # reply written in a different script (conf ≥ 0.85) still does.
        out["language"] = prior.get("language");
    }
    out["case_text"] = (str(prior.get("case_text", "")) + " \n " + str(text))[-1500:];
    answered = list(prior.get("answered", []));
    if answering {
        if answering not in answered { answered.append(answering); }
        low = str(text).lower();
        # "Do you have a safe place to sleep tonight?" / "Are you safe at home?"
        # are asked in the negative: a "no" is the evidence.
        yn = yes_no(text);
        affirm = (re.search(NO_RE, low) or yn == "no") if answering in NEGATIVE_QUESTIONS else (re.search(YES_RE, low) or yn == "yes");
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
    # A household inferred from children or a partner never shrinks one given
    # earlier ("we are 4", later "my partner hits me"); a stated count wins.
    if not cur.get("household_stated") and int(prior.get("household_size", 0) or 0) > int(out.get("household_size", 0) or 0) {
        out["household_size"] = prior.get("household_size");
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
        if out.get("llm_reason", "") == "unrecognized language" and out.get("category") {
            out["needs_llm"] = False;
            out["llm_reason"] = "";
        }
    }
    flags = list(cur.get("flags", []));
    for f in list(prior.get("flags", [])) {
        if f not in flags { flags.append(f); }
    }
    if out.get("answered_yes") and ANSWER_FLAGS.get(str(out["answered_yes"])) and ANSWER_FLAGS[str(out["answered_yes"])] not in flags {
        flags.append(ANSWER_FLAGS[str(out["answered_yes"])]);
    }
    out["flags"] = flags;
    # "How many people live in your household?" → "3", "three", "there are 3 people".
    if answering == "household" and int(out.get("household_size", 0) or 0) <= 0 {
        mc = re.search("\\b(\\d{1,2}|" + "|".join(COUNT_WORDS.keys()) + ")\\b", str(text).lower());
        if mc {
            tok = mc.group(1);
            n = int(tok) if tok.isdigit() else int(COUNT_WORDS.get(tok, 0));
            if 0 < n < 20 { out["household_size"] = n; }
        }
    }
    # "About how much does your household earn per month?" → "2000", "两千五".
    if answering == "income" and int(out.get("income_annual", -1)) < 0 {
        annual = answer_income(str(text));
        if annual >= 0 { out["income_annual"] = annual; }
    }
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

"""Annual income from a bare answer to the income question, or -1.

"2000", "about 2,000", "1.500", "2k", "两千五", "nothing", "15 an hour". Only
a bare amount counts; "we are 2" answers something else and is left to the
parser. The question asks per month, so an amount with no pay period is
monthly unless it is 5,000 or more, as in parse.jac.
"""
def answer_income(text: str) -> int {
    t = ascii_digits(str(text)).strip().lower();
    if re.search("^(?:0|zero|cero|nothing|none|nada|没有|沒有)(?!\\w)", t) {
        return 0;
    }
    rest = re.sub("[零〇一二两兩三四五六七八九十百千万萬]", " ", re.sub(ANSWER_FILLER, " ", t));
    if re.search("[^\\W\\d_]", rest) {
        return -1;
    }
    amount = -1;
    m = re.search("(?<![\\d.,])(\\d{1,3}(?:[,.]\\d{3})+|\\d{1,7})(?:[.,]\\d{1,2})?(?![\\d.,])\\s*(k\\b)?", t);
    if m {
        amount = int(re.sub("[,.]", "", m.group(1))) * (1000 if m.group(2) else 1);
    } else {
        zm = re.search("[零〇一二两兩三四五六七八九十百千万萬]+", t);
        if zm { amount = zh_number(zm.group(0)); }
    }
    if amount < 0 { return -1; }
    if re.search("\\b(?:hour|hr|hora)s?\\b|小时|小時", t) { return amount * 2080; }
    if re.search("\\b(?:week|wk|semana)s?\\b|周|週|星期", t) { return amount * 52; }
    if re.search("\\b(?:year|yr|a[nñ]o|annual|anual)s?\\b|年", t) { return amount; }
    return amount * 12 if amount < 5000 else amount;
}

"""Language the reply is composed in: the user's when a catalog covers it."""
def reply_language(lang: str) -> str {
    if lang in ["en", "es"] or has_messages(lang) { return lang; }
    return "en";
}

"""Reply from the message catalog: the same sentences as EN/ES, in `lang`."""
def compose_catalog(lang: str, profile: dict, ranking: dict, plan: dict, routes: list, question: str) -> str {
    ranked = list(ranking.get("ranked", []));
    likely = [s for s in ranked if s["tier"] == "likely"];
    maybe = [s for s in ranked if s["tier"] in ["possible", "needs_info"]];
    steps = list(plan.get("steps", []));
    pinned = [s for s in ranked if s.get("pinned", False)];
    if profile.get("defaulted_category") and not pinned {
        return msg(lang, "r.unsure");
    }
    lines: list = [];
    if pinned {
        lines.append(msg(lang, "r.safety", {"name": pinned[0]["resource_name"], "phone": pinned[0]["contact_phone"]}));
    }
    if likely and maybe {
        lines.append(msg(lang, "r.found_more", {"n": len(likely), "m": len(maybe)}));
    } elif likely {
        lines.append(msg(lang, "r.found", {"n": len(likely)}));
    } elif maybe {
        lines.append(msg(lang, "r.maybe", {"m": len(maybe)}));
    } else {
        lines.append(msg(lang, "r.none"));
    }
    if steps {
        lines.append(msg(lang, "r.start", {"agency": steps[0]["agency_name"], "action": steps[0]["action_description"]}));
    }
    if routes {
        r = routes[0];
        lines.append(msg(lang, "r.route", {"start": r["start"], "end": r["end"], "days": r["total_days"]}));
    }
    if question {
        lines.append(msg(lang, "r.question", {"question": question}));
    }
    return "\n\n".join(lines);
}

"""Deterministic reply text. EN/ES here; other catalog languages via
compose_catalog; anything else in English (translated after, off the
critical path). Real newlines; **bold** is rendered by the UI."""
def compose_reply(lang: str, profile: dict, ranking: dict, plan: dict, routes: list, question: str) -> str {
    if reply_language(lang) not in ["en", "es"] {
        return compose_catalog(lang, profile, ranking, plan, routes, question);
    }
    es = lang == "es";
    ranked = list(ranking.get("ranked", []));
    likely = [s for s in ranked if s["tier"] == "likely"];
    maybe = [s for s in ranked if s["tier"] in ["possible", "needs_info"]];
    steps = list(plan.get("steps", []));
    pinned = [s for s in ranked if s.get("pinned", False)];
    lines: list = [];

    if profile.get("defaulted_category") and not pinned {
        lines.append("No estoy seguro de qué tipo de ayuda busca. Elija una opción abajo o cuénteme un poco más; mientras tanto, el **211** conecta con ayuda local las 24 horas." if es else "I'm not sure yet what kind of help you need. Pick one below or tell me a little more — meanwhile, **211** connects you to local help 24/7.");
        return "\n\n".join(lines);
    }
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
