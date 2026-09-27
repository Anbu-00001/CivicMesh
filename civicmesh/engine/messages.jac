"""Message catalog — every fixed sentence of an answer, translated ahead of time.

Everything the engine says is a template filled with facts (program names,
phone numbers, counts): the follow-up question, its quick replies, the
suggestion chips, the reply sentences, plan steps and card labels. Those
templates are translated once and kept as data (data/i18n/<code>.json, one
file per language, English is the source), then composed at request time.
So the whole answer is in the user's language on the first response: no
translation call on the critical path, nothing to time out or rate-limit, and
the numbers are the engine's own.

Machine translation stays for what can't be templated (free text) and for
languages without a catalog yet (llm/translate.jac). Catalog files are
machine-drafted and marked for native-speaker review in their _meta.
"""

import json;
import os;

glob MESSAGES: dict = {};
# Right-to-left languages: a phone number after an Arabic-script word would
# be reordered by the bidi algorithm ("1-800-221-5689" shown as
# "5689-221-800-1"), so phone numbers are wrapped in an LTR isolate.
glob RTL_LANGS: list = ["ar", "fa", "ur", "ps", "ckb", "he", "yi"];

"""The i18n directory next to data/resources.json."""
def messages_dir -> str {
    for c in [os.path.join(os.getcwd(), "data", "i18n"), os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "i18n")] {
        if os.path.isdir(c) { return c; }
    }
    return "";
}

"""Load every catalog once (code → {key: text})."""
def load_messages -> dict {
    if MESSAGES { return MESSAGES; }
    d = messages_dir();
    if not d { return MESSAGES; }
    for f in sorted(os.listdir(d)) {
        if f.endswith(".json") {
            MESSAGES[f[:-5]] = json.load(open(os.path.join(d, f), encoding="utf-8"));
        }
    }
    return MESSAGES;
}

"""Keys a catalog needs before the engine composes a whole answer in it."""
def required_keys -> list {
    return [k for k in load_messages().get("en", {}).keys() if not k.startswith("_")];
}

"""True when `lang` has a complete catalog (every English key)."""
def has_messages(lang: str) -> bool {
    table = load_messages().get(str(lang), {});
    if not table { return False; }
    for k in required_keys() {
        if not table.get(k) { return False; }
    }
    return True;
}

"""Languages with a complete catalog."""
def message_languages -> list {
    return [c for c in sorted(load_messages().keys()) if has_messages(c)];
}

"""Text for `key` in `lang` (English if missing), with {placeholders} filled."""
def msg(lang: str, key: str, params: dict = {}) -> str {
    cat = load_messages();
    s = str(cat.get(str(lang), {}).get(key, "") or cat.get("en", {}).get(key, key));
    for (k, v) in params.items() {
        val = str(v);
        if k == "phone" and val and str(lang) in RTL_LANGS { val = "\u2066" + val + "\u2069"; }
        s = s.replace("{" + str(k) + "}", val);
    }
    return s;
}

"""Labels the client renders (card chrome, quick replies), in `lang`."""
def ui_labels(lang: str) -> dict {
    out: dict = {};
    for k in required_keys() {
        if k.startswith("ui.") or k.startswith("opt.") { out[k] = msg(lang, k); }
    }
    return out;
}

"""Quick replies for a question key: [label in `lang`, English payload].

The payload stays English (the engine parses it the same way for every
language); the client pins the case language when sending it.
"""
def quick_options(key: str, lang: str) -> list {
    yes_no = ["homeless", "veteran", "disability", "dv", "young_child", "children", "eviction"];
    rows: list = [];
    if key in yes_no {
        rows = [["opt.yes", "yes"], ["opt.no", "no"]];
    } elif key == "need" {
        rows = [["opt.food", "I need food"], ["opt.housing", "I need help with housing"], ["opt.health", "I need a doctor"], ["opt.legal", "I need a lawyer"]];
    } elif key == "income" {
        rows = [["opt.inc1", "about $800 a month"], ["opt.inc2", "about $1,500 a month"], ["opt.inc3", "about $2,500 a month"], ["opt.inc4", "about $3,500 a month"], ["opt.inc0", "no income"]];
    } elif key == "household" {
        rows = [["opt.just_me", "just me"], ["2", "household of 2"], ["3", "household of 3"], ["4", "household of 4"], ["5+", "household of 5"]];
    } elif key == "citizenship" {
        rows = [["opt.citizen", "I'm a US citizen"], ["opt.green_card", "I have a green card"], ["opt.refugee", "I'm a refugee"], ["opt.no_status", "I'm undocumented"]];
    }
    return [[(msg(lang, r[0]) if r[0].startswith("opt.") else r[0]), r[1]] for r in rows];
}
