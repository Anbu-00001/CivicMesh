"""Differential check of four income-tested programs against PolicyEngine US.

tools/oracle_policyengine.py covers SNAP. This covers the other programs whose
income test the engine computes: Medicaid for adults, Medicaid/CHIP for
children, school meals (free or reduced price) and WIC's income test. The
same households go through engine/policy.jac's income_limit() and through
PolicyEngine; every disagreement is printed with both answers. As with SNAP,
a disagreement is a lead, not a verdict: either model can be wrong, and some
are deliberate simplifications (one national CHIP figure, documented as
"typical", where states set 170% to 400%).

    python3 -m venv pe && pe/bin/pip install policyengine-us
    sh tools/eject_engine.sh ../civicmesh-engine-python
    PYTHONPATH=../civicmesh-engine-python pe/bin/python tools/oracle_programs.py [month]

Grid: 12 states (6 that expanded Medicaid, 5 that didn't, and Wisconsin),
U.S.-citizen households of 1 adult (Medicaid only) and 1 adult with 2
children, incomes from 0 to 300% of poverty, all earned at 30 hours a week
(so no work rule applies). Children are 7 and 10 (school meals, CHIP); WIC
uses a household with a 2-year-old.
"""

import os
import sys

MONTH = sys.argv[1] if len(sys.argv) > 1 else "2026-10"
os.environ["CIVICMESH_POLICY_DATE"] = MONTH + "-01"

from policyengine_us import Simulation  # noqa: E402

from engine.policy import fpl_annual, income_limit  # noqa: E402

YEAR = MONTH[:4]
STATES = ["CA", "NY", "IL", "CO", "AZ", "OH", "TX", "FL", "GA", "KS", "TN", "WI"]
FPL_PCTS = [0, 50, 90, 120, 135, 145, 170, 190, 220, 260, 300]


def situation(state, kids_ages, annual):
    people = {"p0": {"age": {YEAR: 35}, "employment_income": {YEAR: annual}, "weekly_hours_worked": {YEAR: 30}}}
    for i, a in enumerate(kids_ages):
        people[f"c{i}"] = {"age": {YEAR: a}, "is_in_k12_school": {YEAR: a >= 5}}
    members = list(people)
    return {
        "people": people,
        "tax_units": {"tu": {"members": members}},
        "families": {"fam": {"members": members}},
        "spm_units": {"spm": {"members": members}},
        "households": {"hh": {"members": members, "state_code": {YEAR: state}}},
        "marital_units": {f"mu{m}": {"members": [m]} for m in members},
    }


def ours(rule_id, state, n, annual, flags):
    lim = income_limit(rule_id, {"household_size": n, "state": state, "flags": flags, "citizenship": "citizen", "income_annual": annual})
    if lim.get("blocked"):
        return False
    if lim.get("none"):  # no income test here (universal school meals)
        return True
    return annual <= int(lim["limit"])


def check(name, rule_id, kids, flags, pe_fn):
    rows = []
    for state in STATES:
        n = 1 + len(kids)
        for pct in FPL_PCTS:
            annual = int(round(fpl_annual(n, state) * pct / 100.0))
            sim = Simulation(situation=situation(state, kids, annual))
            rows.append((state, n, pct, ours(rule_id, state, n, annual, flags), bool(pe_fn(sim))))
    agree = [r for r in rows if r[3] == r[4]]
    print(f"{name:<34} eligibility agrees {len(agree)}/{len(rows)} ({len(agree) / len(rows):.1%})")
    for r in rows:
        if r[3] != r[4]:
            print(f"    {r[0]} n={r[1]} {r[2]:>3}% FPL   ours {'eligible' if r[3] else 'not':<8}  PolicyEngine {'eligible' if r[4] else 'not'}")
    return len(agree), len(rows)


def first(sim, var, period=YEAR):
    return sim.calculate(var, period)[0]


print(f"PolicyEngine US vs CivicMesh income tests, {MONTH}")
totals = [
    check("Medicaid, adult without children", "medicaid-rule", [], [], lambda s: first(s, "is_medicaid_eligible")),
    check("Medicaid, parent of two", "medicaid-rule", [7, 10], ["children"], lambda s: first(s, "is_medicaid_eligible")),
    check("Medicaid or CHIP, the children", "chip-rule", [7, 10], ["children"],
          lambda s: s.calculate("is_medicaid_eligible", YEAR)[1] or s.calculate("is_chip_eligible", YEAR)[1]),
    check("School meals, free or reduced", "nslp-rule", [7, 10], ["children"],
          lambda s: str(s.calculate("school_meal_tier", YEAR).decode_to_str()[0]) != "PAID"),
    check("WIC income test, child of 2", "wic-rule", [2], ["children"], lambda s: s.calculate("meets_wic_income_test", YEAR)[-1]),
]
ok = sum(t[0] for t in totals)
n = sum(t[1] for t in totals)
print(f"all four programs                  {ok}/{n} ({ok / n:.1%})")
