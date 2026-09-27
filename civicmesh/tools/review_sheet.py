"""Side-by-side review sheet for one message catalog (stdlib only, no Jac).

    python3 tools/review_sheet.py zh > zh-review.md
    python3 tools/review_sheet.py --status          # review state of every catalog

The sheet lists every string as English | translation, safety-critical ones
first (crisis lines, the safety question, the machine-translation notice,
immigration status), with the placeholders that must survive. A reviewer
edits data/i18n/<code>.json directly, or pastes corrections into a
"Translation review" issue. See docs/TRANSLATION_REVIEW.md.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
I18N = os.path.join(HERE, "..", "data", "i18n")

# Reviewed first, and by two people before a catalog is marked "reviewed":
# a wrong word here can send someone to the wrong place in a crisis.
SAFETY = [
    "esc.self_harm", "esc.dv", "esc.call", "esc.interp", "r.safety", "q.dv", "q.homeless",
    "chip.homeless", "r.unsure", "act.call", "act.in_person", "ui.mt_draft",
    "q.citizenship", "opt.no_status", "opt.refugee", "opt.green_card",
]


def load(code):
    with open(os.path.join(I18N, code + ".json"), encoding="utf-8") as f:
        return json.load(f)


def status():
    rows = []
    for f in sorted(os.listdir(I18N)):
        if not f.endswith(".json") or f == "en.json":
            continue
        meta = load(f[:-5]).get("_meta", {})
        review = str(meta.get("review", ""))
        rows.append((f[:-5], meta.get("name", ""), "reviewed" if review.lower().startswith("reviewed") else "draft", review))
    print("| code | language | state | note |\n|---|---|---|---|")
    for r in rows:
        print("| " + " | ".join(r) + " |")
    print("\n" + str(sum(1 for r in rows if r[2] == "reviewed")) + " of " + str(len(rows)) + " catalogs reviewed by a native speaker.")


def cell(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def sheet(code):
    en = load("en")
    tr = load(code)
    meta = tr.get("_meta", {})
    keys = [k for k in en if not k.startswith("_")]
    order = [k for k in SAFETY if k in keys] + [k for k in keys if k not in SAFETY]
    print("# Review sheet — " + str(meta.get("name", code)) + " (" + code + ")\n")
    print("State: **" + str(meta.get("review", "draft")) + "**. Check meaning, tone (plain, respectful, "
          "no legal promises) and that every {placeholder}, number and **bold** marker survives. "
          "Rows 1–" + str(len([k for k in SAFETY if k in keys])) + " are safety-critical.\n")
    print("| # | key | English | " + str(meta.get("name", code)) + " | ok? |\n|---|---|---|---|---|")
    for i, k in enumerate(order, 1):
        mark = " ⚠" if k in SAFETY else ""
        print("| " + str(i) + " | `" + k + "`" + mark + " | " + cell(en[k]) + " | " + cell(tr.get(k, "**MISSING**")) + " | |")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    if sys.argv[1] == "--status":
        status()
    else:
        sheet(sys.argv[1])
