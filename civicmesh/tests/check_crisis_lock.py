"""Every catalog's crisis sentences, locked word for word (audit list C14).

check_messages.jac keeps the numbers the same in every catalog, but a changed
word with the same digits passed: a mutation turning Spanish "oprima 1" into
"oprima uno" survived it. This compares each crisis sentence with a hash
recorded when a person last looked at it, so any edit has to be made on purpose.

    python3 tests/check_crisis_lock.py            (from civicmesh/)
    python3 tests/check_crisis_lock.py --update   (after a deliberate change, reviewed)
"""

import glob
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGS = os.path.join(HERE, "..", "data", "i18n")
LOCK = os.path.join(HERE, "crisis_sentences.lock.json")
KEYS = ["r.emergency", "r.crisis_net", "r.more_lines", "r.safety", "ui.safety_danger",
        "q.safety", "opt.s_danger", "opt.s_hurt", "opt.s_suicide", "opt.s_child", "opt.s_safe"]


def current() -> dict:
    out = {}
    for path in sorted(glob.glob(os.path.join(CATALOGS, "*.json"))):
        lang = os.path.basename(path)[:-5]
        cat = json.load(open(path, encoding="utf-8"))
        out[lang] = {k: hashlib.sha256(str(cat.get(k, "")).encode("utf-8")).hexdigest()[:16] for k in KEYS}
    return out


def main() -> int:
    now = current()
    if "--update" in sys.argv:
        with open(LOCK, "w", encoding="utf-8") as f:
            json.dump(now, f, indent=1, sort_keys=True)
            f.write("\n")
        print(f"crisis lock: wrote {len(now)} catalogs x {len(KEYS)} sentences")
        return 0
    locked = json.load(open(LOCK, encoding="utf-8"))
    fails = []
    for lang in sorted(set(now) | set(locked)):
        for k in KEYS:
            if now.get(lang, {}).get(k) != locked.get(lang, {}).get(k):
                fails.append(f"{lang}: {k} changed (or is new/missing)")
    for f in fails:
        print("  FAIL " + f)
    print(f"crisis lock: {len(now)} catalogs x {len(KEYS)} sentences, {len(fails)} changed")
    if fails:
        print("  If the change is deliberate and checked, run: python3 tests/check_crisis_lock.py --update")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
