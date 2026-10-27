"""Every program has a verification record, and none is older than a year.

    python3 tests/check_verification.py        (from civicmesh/)

Benefit rules and phone numbers change every fiscal year, and a catalog
nobody re-checks drifts: the contact check of 2026-10-27 found three phone
numbers that belonged to someone else and two dead links. This gate makes the
age of each check visible and fails CI once any record passes MAX_AGE_DAYS,
so re-checking is a scheduled job (docs/MAINTENANCE.md), not a hope.
"""

import datetime
import json
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAX_AGE_DAYS = 365


def main():
    progs = json.load(open(os.path.join(HERE, "data", "resources.json"), encoding="utf-8"))["resources"]
    ver = json.load(open(os.path.join(HERE, "data", "verification.json"), encoding="utf-8"))["programs"]
    today = datetime.date.today()
    fails = []
    confirmed = rules = 0
    for p in progs:
        rid = p["eligibility"]["rule_id"]
        rec = ver.get(rid)
        if not rec:
            fails.append(f"{rid}: no verification record (run tools/check_contacts.py)")
            continue
        dates = [rec.get("contact_checked")] + [(rec.get("contact_manual") or {}).get("checked")]
        newest = max(datetime.date.fromisoformat(d) for d in dates if d)
        age = (today - newest).days
        if age > MAX_AGE_DAYS:
            fails.append(f"{rid}: contact last checked {newest} ({age} days ago)")
        if rec.get("contact_result") == "confirmed" or rec.get("contact_manual"):
            confirmed += 1
        rule_date = (rec.get("rules") or {}).get("checked")
        if rule_date:
            rules += 1
            if (today - datetime.date.fromisoformat(rule_date)).days > MAX_AGE_DAYS:
                fails.append(f"{rid}: rules last checked {rule_date}")
    stale = set(ver) - {p["eligibility"]["rule_id"] for p in progs}
    for rid in sorted(stale):
        fails.append(f"{rid}: record for a program that is no longer in the catalog")
    print(f"verification: {len(progs)} programs · contacts confirmed or checked by hand {confirmed} · "
          f"rules checked against an independent source {rules}")
    for f in fails:
        print("  FAIL", f)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
