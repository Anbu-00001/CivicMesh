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
import re
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
    # Every number a person is told to call has been confirmed on the
    # program's page or checked by hand (outside judge, 2026-10-28: federal
    # headquarters lines were plan step 1). 2-1-1, 911 and 988 are universal.
    universal = {"", "2-1-1", "211", "911", "988"}
    checked = set(universal)
    for p in progs:
        rec = ver.get(p["eligibility"]["rule_id"]) or {}
        phone = str(p.get("contact_phone", ""))
        if phone in universal or rec.get("contact_result") == "confirmed" or rec.get("contact_manual"):
            checked.add(phone)
        else:
            fails.append(f"{p['eligibility']['rule_id']}: phone {phone} is shown but neither confirmed nor checked by hand")
    esc = open(os.path.join(HERE, "walkers", "escalation.jac"), encoding="utf-8").read()
    leads = esc[esc.index("glob LEADS"):esc.index("};", esc.index("glob LEADS"))]
    for phone in re.findall(r'^\s*"\w+": \("[^"]*", "([^"]*)"', leads, re.M):
        if phone not in checked:
            fails.append(f"escalation lead {phone} is not a checked catalog number")
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
