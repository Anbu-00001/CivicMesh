"""Message-catalog check: every data/i18n/<code>.json against the English source.

For each language: every key present and non-empty, the same {placeholders},
the same numbers (1,000 / 1.000 / 1 000 all count as 1000; digits in other
scripts are mapped first), the same **bold** markers, and a round trip — the
language detector must read the catalog's own questions as that language
(which also tests the detector).

    jac run tests/check_messages.jac          (from civicmesh/)

Exit code is non-zero on any failure.
"""

import re;
import sys;
import from engine.messages { load_messages, required_keys, has_messages }
import from engine.parse { detect_language }
import from engine.i18n { ascii_digits }

# Written varieties the detector may legitimately report for a catalog.
glob ALSO_READS_AS: dict = {"yue": ["zh"], "zh": ["yue"]};

def numbers(s: str) -> list {
    t = re.sub(r"(?<=\d)[,.\s  ](?=\d{3}(?!\d))", "", ascii_digits(str(s)));
    return sorted(re.findall(r"\d+", t));
}

with entry {
    cat = load_messages();
    en = cat["en"];
    keys = required_keys();
    fails: list = [];
    langs = sorted([c for c in cat.keys() if c != "en"]);
    for code in langs {
        t = cat[code];
        for k in keys {
            v = str(t.get(k, "") or "");
            if not v {
                fails.append(code + ": missing " + k);
                continue;
            }
            if sorted(re.findall(r"\{[a-z]+\}", str(en[k]))) != sorted(re.findall(r"\{[a-z]+\}", v)) {
                fails.append(code + ": placeholders differ in " + k);
            }
            if numbers(str(en[k])) != numbers(v) {
                fails.append(code + ": numbers differ in " + k + " (" + ",".join(numbers(v)) + ")");
            }
            if str(en[k]).count("**") != v.count("**") {
                fails.append(code + ": bold markers differ in " + k);
            }
        }
        extra = [k for k in t.keys() if not k.startswith("_") and k not in en];
        if extra { fails.append(code + ": keys not in en.json: " + ", ".join(extra)); }
        qs = " ".join([str(t.get(k, "")) for k in keys if k.startswith("q.")]);
        (got, _conf) = detect_language(qs);
        if got != code and got not in ALSO_READS_AS.get(code, []) {
            fails.append(code + ": its questions are detected as '" + str(got) + "'");
        }
    }
    complete = [c for c in langs if has_messages(c)];
    print("Message catalogs: " + str(len(langs)) + " languages + English source, " + str(len(keys)) + " keys each");
    print("  complete: " + str(len(complete)) + " → " + " ".join(complete));
    for f in fails { print("  ✗ " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
