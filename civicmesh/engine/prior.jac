"""The previous turn's profile, as the client sends it back, made safe to merge.

The case lives in the browser (nothing about it is stored server-side), so
`prior` arrives as the client sent it. A forged household of 12 and forged
flags were scored as given (outside judge, 2026-10-28). The effect was
limited to the sender's own answer, but the engine should only reason from
facts it could have parsed itself: every field is type- and range-checked,
unknown keys are dropped, and a flag is kept only when the case text the
person actually wrote still supports it. Retractions survive, because a flag
taken back is already missing from `prior`.
"""

import re;
import from engine.parse { parse_intake, STATES }
import from engine.compose { ANSWER_EVIDENCE, ANSWER_FLAGS, COUNT_WORDS }

glob CATEGORIES: list = ["housing", "food", "healthcare", "legal"];
glob CITIZENSHIP: list = ["citizen", "citizen_or_lpr", "eligible_immigrant", "humanitarian", "non_citizen", "cuban_haitian_entrant", "cofa"];
glob URGENCY: list = ["immediate", "within_days", "within_weeks"];
glob ANSWER_KEYS: list = ["need", "income", "household", "age", "location", "citizenship", "homeless", "dv", "veteran", "disability", "children", "young_child", "eviction", "minor"];

def _int_in(v: any, lo: int, hi: int, fallback: int) -> int {
    try {
        n = int(float(v));
    } except Exception {
        return fallback;
    }
    return n if lo <= n <= hi else fallback;
}

def _str(v: any, limit: int) -> str {
    return str(v)[:limit] if isinstance(v, str) else "";
}

"""A prior profile with only checked fields; {} for anything that isn't a dict."""
def sanitize_prior(prior: any) -> dict {
    if not isinstance(prior, dict) or not prior {
        return {};
    }
    out: dict = {};
    case_text = _str(prior.get("case_text", ""), 1500);
    out["case_text"] = case_text;
    out["income_annual"] = _int_in(prior.get("income_annual", -1), -1, 10000000, -1);
    out["household_size"] = _int_in(prior.get("household_size", 0), 0, 20, 0);
    out["age"] = _int_in(prior.get("age", 0), 0, 120, 0);
    st = _str(prior.get("state", ""), 2).upper();
    out["state"] = st if st in STATES.values() else "";
    city = _str(prior.get("city", ""), 60);
    out["city"] = city if re.fullmatch(r"[^\W\d_][\w .'\-]*", city) else "";
    z = _str(prior.get("zip", ""), 5);
    out["zip"] = z if re.fullmatch(r"\d{5}", z) else "";
    c = _str(prior.get("citizenship", ""), 32);
    out["citizenship"] = c if c in CITIZENSHIP else "";
    lang = _str(prior.get("language", ""), 12);
    out["language"] = lang if re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z]{2,4})?", lang) else "";
    cat = _str(prior.get("category", ""), 16);
    out["category"] = cat if cat in CATEGORIES else "";
    sec = prior.get("secondary", []);
    out["secondary"] = [s for s in sec if isinstance(s, str) and s in CATEGORIES and s != out["category"]][:3] if isinstance(sec, list) else [];
    try {
        conf = float(prior.get("category_conf", 0.5));
    } except Exception {
        conf = 0.5;
    }
    out["category_conf"] = conf if 0.0 <= conf <= 1.0 else 0.5;
    u = _str(prior.get("urgency", ""), 16);
    out["urgency"] = u if u in URGENCY else "within_weeks";
    ans = prior.get("answered", []);
    out["answered"] = [a for a in ans if isinstance(a, str) and a in ANSWER_KEYS][:20] if isinstance(ans, list) else [];
    out["household_stated"] = prior.get("household_stated") is True;
    out["age_other"] = prior.get("age_other") is True;
    # Flags: only those the person's own words still support.
    fl = prior.get("flags", []);
    claimed = [f for f in fl if isinstance(f, str)][:40] if isinstance(fl, list) else [];
    reparsed: dict = parse_intake(case_text) if case_text else {};
    supported = list(reparsed.get("flags", []));
    # A household count must come from the words too: the re-parse, or the
    # number itself as a reply to "How many people live in your household?".
    hh = out["household_size"];
    if hh > 0 and int(reparsed.get("household_size", 0) or 0) != hh and not [seg for seg in case_text.split("\n") if int(parse_intake(seg).get("household_size", 0) or 0) == hh] and not re.search("\\b(?:" + str(hh) + "|" + "|".join([w for (w, n) in COUNT_WORDS.items() if n == hh] or ["\\b\\B"]) + ")\\b", case_text.lower()) {
        out["household_size"] = int(reparsed.get("household_size", 0) or 0);
        out["household_stated"] = False;
    }
    # A quick-reply answer appends its evidence word after the reply ("no
    # homeless" for "Do you have a safe place to sleep?" → "no"), which a
    # re-parse reads as negated: an answered question with its evidence in
    # the text still grounds its flag, and so does a checked age.
    for (key, flag) in ANSWER_FLAGS.items() {
        if key in out["answered"] and (" " + str(ANSWER_EVIDENCE.get(key, "?"))) in case_text { supported.append(flag); }
    }
    if out["age"] >= 60 { supported.append("senior"); }
    if 0 < out["age"] < 18 { supported.append("minor"); }
    out["flags"] = [f for f in claimed if f in supported];
    return out;
}
