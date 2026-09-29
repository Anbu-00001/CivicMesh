"""Differential check of the SNAP estimate against PolicyEngine US.

PolicyEngine US is an independent, open-source microsimulation of federal and
state benefit rules. This runs the same households through both and reports
where they disagree. Disagreements are leads to investigate, not ground
truth: either model can be wrong, and PolicyEngine models deductions this
engine leaves out on purpose.

    # a venv with PolicyEngine (heavy; not a CI dependency)
    python3 -m venv pe && pe/bin/pip install policyengine-us
    # this engine as plain Python (see tools/eject_engine.sh)
    sh tools/eject_engine.sh ../civicmesh-engine-python
    PYTHONPATH=../civicmesh-engine-python pe/bin/python tools/oracle_policyengine.py [month]

The grid: 12 states chosen to span the gross-income limits in USDA's broad-
based categorical eligibility chart (130% to 200%), households of 1, 2 and 4,
incomes from 0 to 205% of poverty; working adults (30 hours a week, so the
work rules don't apply) with children in larger households; and seniors living
on Social Security. No rent or utilities are entered, so both sides compute
the benefit from income and the standard deduction only.
"""

import json
import os
import sys

MONTH = sys.argv[1] if len(sys.argv) > 1 else "2026-10"
os.environ["CIVICMESH_POLICY_DATE"] = MONTH + "-01"

from policyengine_us import Simulation  # noqa: E402

from engine.policy import fpl_annual, snap_estimate  # noqa: E402

YEAR = MONTH[:4]
STATES = ["CA", "CO", "AZ", "NJ", "IL", "TX", "IA", "NY", "ID", "GA", "OH", "KS"]
SIZES = [1, 2, 4]
FPL_PCTS = [0, 50, 100, 125, 140, 160, 175, 190, 205]


def situation(state, n, annual, senior):
    people = {}
    if senior:
        people["p0"] = {"age": {YEAR: 70}, "social_security_retirement": {YEAR: annual}}
    else:
        people["p0"] = {"age": {YEAR: 35}, "employment_income": {YEAR: annual}, "weekly_hours_worked": {YEAR: 30}}
    for i in range(1, n):
        people[f"p{i}"] = {"age": {YEAR: 70 if senior else 4 + 3 * i}}
    members = list(people)
    return {
        "people": people,
        "tax_units": {"tu": {"members": members}},
        "families": {"fam": {"members": members}},
        "spm_units": {"spm": {"members": members}},
        "households": {"hh": {"members": members, "state_code": {YEAR: state}}},
        "marital_units": {f"mu{m}": {"members": [m]} for m in members},
    }


def ours(state, n, annual, senior):
    flags = ["senior", "unearned_income"] if senior else (["children"] if n > 1 else [])
    est = snap_estimate({"household_size": n, "income_annual": annual, "state": state, "flags": flags, "age": 70 if senior else 35})
    return int(est.get("monthly", 0)) if est else 0


def theirs(state, n, annual, senior):
    sim = Simulation(situation=situation(state, n, annual, senior))
    return int(round(float(sim.calculate("snap", MONTH)[0])))


rows = []
for state in STATES:
    for n in SIZES:
        for pct in FPL_PCTS:
            annual = int(round(fpl_annual(n, state) * pct / 100.0))
            rows.append((state, n, pct, "earned", ours(state, n, annual, False), theirs(state, n, annual, False)))
for state in STATES:
    for pct in [50, 90, 120, 150, 180]:
        annual = int(round(fpl_annual(1, state) * pct / 100.0))
        rows.append((state, 1, pct, "senior-ss", ours(state, 1, annual, True), theirs(state, 1, annual, True)))

agree_elig = [r for r in rows if (r[4] > 0) == (r[5] > 0)]
both = [r for r in rows if r[4] > 0 and r[5] > 0]
close = [r for r in both if abs(r[4] - r[5]) <= 5]
print(f"PolicyEngine US vs CivicMesh SNAP estimate, {MONTH} — {len(rows)} households")
print(f"  eligibility agrees     {len(agree_elig)}/{len(rows)} ({len(agree_elig) / len(rows):.1%})")
print(f"  amount within $5       {len(close)}/{len(both)} of households both call eligible")
dis = [r for r in rows if (r[4] > 0) != (r[5] > 0) or (r[4] > 0 and r[5] > 0 and abs(r[4] - r[5]) > 5)]
print(f"  disagreements          {len(dis)}")
for r in dis[:40]:
    print(f"    {r[0]} n={r[1]} {r[2]:>3}% FPL {r[3]:<9}  ours ${r[4]:>5}  PolicyEngine ${r[5]:>5}")
if "--json" in sys.argv:
    json.dump([dict(zip(["state", "n", "fpl_pct", "income", "ours", "policyengine"], r)) for r in rows], open("oracle_snap.json", "w"), indent=1)
