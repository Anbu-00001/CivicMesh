"""Policy-date checks (engine/policy.jac) — no server, no LLM.

    jac run tests/check_policy.jac

The numbers here are copied from the primary sources, not from the engine,
so a typo in a table fails the run:

1. SNAP switches from FY2026 to FY2027 on October 1, 2026 (USDA memo of
   2026-08-21): max allotments, standard deductions, minimum benefit, the
   18-person cap, Alaska and Hawaii.
2. SNAP's gross limit is the state's (USDA broad-based categorical
   eligibility chart, June 2026); under it there is no net test, over it
   only an elderly or disabled household can qualify, through the net test.
   The 20% deduction is for earnings only (not Social Security, SSI or a
   pension).
3. P.L. 119-21: refugees lose federally funded Medicaid on 2026-10-01; the
   SNAP time limit (18–64, no child under 14) and the Medicaid work
   requirement (expansion adults 19–64, from 2027-01-01) are shown as notes
   to the people they can apply to, and not to parents, seniors or people
   with a disability.
4. Non-expansion states: the coverage-gap text says Marketplace subsidies
   start at 100% of poverty instead of calling the Marketplace a fallback.
"""

import os;
import sys;
import json;
import from engine.policy { snap_estimate, snap_year, income_limit, status_rule, fpl_annual }
import from engine.score { score_resource }
import from engine.parse { parse_intake }

glob fails: list = [];
glob total: list = [0];

def check(ok: bool, what: str) -> None {
    total[0] += 1;
    if not ok { fails.append(what); }
}

def on(date: str) -> None {
    os.environ["CIVICMESH_POLICY_DATE"] = date;
}

def prof(n: int, income_mo: int, state: str = "TX", flags: list = [], age: int = 0) -> dict {
    return {"household_size": n, "income_annual": income_mo * 12, "state": state, "flags": list(flags), "age": age, "citizenship": ""};
}

glob SNAP_RES: dict = [r for r in json.load(open("data/resources.json"))["resources"] if r["eligibility"].get("rule_id") == "snap-rule"][0];

with entry {
    # ---- 1. SNAP year switch (USDA FY2027 COLA memo, 2026-08-21) ----
    on("2026-09-30");
    check(snap_year()["fy"] == "FY2026", "Sep 30 2026 is still FY2026");
    check(snap_estimate(prof(4, 0))["monthly"] == 994, "FY2026 max for 4 is $994");
    on("2026-10-01");
    check(snap_year()["fy"] == "FY2027", "Oct 1 2026 starts FY2027");
    fy27 = {1: 306, 2: 562, 3: 808, 4: 1023, 5: 1217, 6: 1463, 7: 1616, 8: 1841, 9: 2066, 17: 3866, 18: 3887, 25: 3887};
    for (n, want) in fy27.items() {
        got = snap_estimate(prof(n, 0)).get("monthly");
        check(got == want, f"FY2027 max for {n} people: want {want}, got {got}");
    }
    check(snap_estimate(prof(4, 0, "AK"))["monthly"] == 1306, "FY2027 Alaska (urban) max for 4 is $1,306");
    check(snap_estimate(prof(4, 0, "HI"))["monthly"] == 1655, "FY2027 Hawaii max for 4 is $1,655");
    # $1,700/mo earned, 1 person: net = 1700*0.8 - 217 = 1143 (under $1,330) →
    # 306 - 343 < 25, so the $25 minimum.
    check(snap_estimate(prof(1, 1700))["monthly"] == 25, "FY2027 minimum benefit is $25");
    # 4 people, $2,000/mo earned: net = 1600 - 229 = 1371 → 1023 - 411 = 612.
    check(snap_estimate(prof(4, 2000))["monthly"] == 612, "FY2027 4-person standard deduction is $229");
    # 6 people, $3,000/mo earned: net = 2400 - 308 = 2092 → 1463 - 628 = 835.
    check(snap_estimate(prof(6, 3000))["monthly"] == 835, "FY2027 6+ standard deduction is $308");

    # ---- 2. Net test and unearned income ----
    # Kansas keeps the federal 130% gross test ($1,729 for 1): over it, no
    # benefit unless elderly/disabled. Texas's limit is 165% ($2,195).
    check(snap_estimate(prof(1, 1800, "KS")) == {}, "Kansas: over 130% gross → no estimate");
    check(snap_estimate(prof(1, 1800, "TX")).get("monthly", 0) > 0, "Texas: $1,800 is under its 165% limit");
    check(snap_estimate(prof(1, 2300, "TX")) == {}, "Texas: over 165% gross → no estimate");
    # A senior living alone on $3,000/mo Social Security fails the net test
    # (net 2,783 > $1,330); the minimum benefit must not be shown.
    senior_rich = prof(1, 3000, "TX", ["senior", "unearned_income"], 72);
    check(snap_estimate(senior_rich) == {}, "senior over the net limit gets no minimum benefit");
    # $1,200/mo Social Security, 72, alone: net = 1200 - 217 = 983 (no 20%) →
    # 306 - 295 = 11 → $25 minimum. With the earnings deduction it read $83.
    ss = snap_estimate(prof(1, 1200, "IL", ["senior", "unearned_income"], 72));
    check(ss.get("monthly") == 25, f"$1,200 Social Security gets no earnings deduction: got {ss.get('monthly')}");
    check("no earnings deduction" in str(ss.get("basis", "")), "basis says why there's no earnings deduction");
    check("medical" in str(ss.get("basis", "")), "basis tells a senior that medical costs raise it");

    p1 = parse_intake("I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally.");
    check("unearned_income" in p1["flags"], "parser: Social Security income is unearned");
    p2 = parse_intake("I make $1200 a month at my job and need food");
    check("unearned_income" not in p2["flags"], "parser: wages are earned");
    p3 = parse_intake("mi pensión es de $900 al mes y necesito comida");
    check("unearned_income" in p3["flags"], "parser: pensión is unearned");

    # ---- 2b. State gross limits (USDA broad-based categorical eligibility
    # chart, June 2026); family of 4, 2026 poverty line $33,000 ----
    for (st, pct) in {"CA": 200, "CO": 200, "AZ": 200, "NJ": 185, "IL": 165, "TX": 165, "IA": 160, "ID": 130, "GA": 130, "KS": 130}.items() {
        lim = income_limit("snap-rule", prof(4, 3000, st))["limit"];
        check(lim == int(round(33000 * pct / 100.0)), f"{st} SNAP gross limit for 4 is {pct}% (${int(round(33000 * pct / 100.0)):,}), got ${lim:,}");
    }
    check(income_limit("snap-rule", prof(4, 3000, "NY"))["limit"] == 49500, "New York: 150% with earnings");
    check(income_limit("snap-rule", prof(4, 3000, "NY", ["unearned_income"]))["limit"] == 42900, "New York: 130% without earnings");
    check(income_limit("snap-rule", prof(4, 3000, "AR", ["senior"]))["limit"] == 54450, "Arkansas: 165% for an elderly household");
    check(income_limit("snap-rule", prof(4, 3000, ""))["limit"] == 42900, "unknown state: federal 130%");
    # Categorically eligible households skip the net test in most states:
    # Texas, 4 people, $4,500/mo earned (164% of poverty, under 165%): net
    # 3,371 is over the $2,750 net limit, yet eligible: 1,023 - 1,011 = $12.
    # California keeps the net test (LA County CalFresh manual; found by the
    # PolicyEngine differential), and Kansas has no broad-based eligibility.
    check(snap_estimate(prof(4, 4500, "TX")).get("monthly") == 12, "Texas: categorical eligibility skips the net test");
    check(snap_estimate(prof(4, 4500, "CA")) == {}, "California: the net test still applies");
    check(snap_estimate(prof(4, 4500, "KS")) == {}, "Kansas: $4,500 for 4 is over 130% gross");
    # State minimums: New Jersey $95 for every household, D.C. $30, Maryland
    # $40 with someone 62+.
    check(snap_estimate(prof(1, 1700, "NJ")).get("monthly") == 95, "New Jersey: $95 state minimum");
    check(snap_estimate(prof(1, 1700, "DC")).get("monthly") == 30, "D.C.: $30 state minimum");
    check(snap_estimate(prof(1, 1200, "MD", ["senior", "unearned_income"], 70)).get("monthly") == 40, "Maryland: $40 minimum at 62+");
    check(snap_estimate(prof(1, 1700, "MD", [], 40)).get("monthly") == 25, "Maryland: federal minimum under 62");
    # 210% of poverty for 4 ($69,300): over every state's limit. Not
    # "possible 41%" any more: unlikely, unless someone is 60+ or disabled.
    rich = prof(4, 5775, "CA");
    check(score_resource(SNAP_RES, SNAP_RES["eligibility"], rich, "we need food")["tier"] == "unlikely", "210% of poverty in California is unlikely for SNAP");
    rich_d = prof(4, 5775, "CA", ["disabled"]);
    check(score_resource(SNAP_RES, SNAP_RES["eligibility"], rich_d, "we need food")["tier"] != "unlikely", "a disabled member keeps the net-test route open");
    mid = prof(4, 4500, "ID");
    sr = score_resource(SNAP_RES, SNAP_RES["eligibility"], mid, "we need food");
    check(sr["tier"] == "unlikely" and "disability" in str(sr), "Idaho at 164%: unlikely, and the card names the elderly/disabled route");
    check(score_resource(SNAP_RES, SNAP_RES["eligibility"], prof(4, 4500, "CA"), "we need food")["tier"] != "unlikely", "California at 164%: still in range");

    # ---- 3. P.L. 119-21 ----
    refugee = {"household_size": 1, "income_annual": 12000, "state": "IL", "flags": [], "age": 30, "citizenship": "humanitarian"};
    on("2026-09-30");
    check(status_rule("medicaid-rule", refugee)["status"] == "met", "refugee Medicaid through Sep 30 2026");
    on("2026-10-01");
    check(status_rule("medicaid-rule", refugee)["status"] == "unmet", "refugee federally funded Medicaid ends Oct 1 2026");
    check(status_rule("snap-rule", refugee)["status"] == "unmet", "refugee SNAP ended Jul 4 2025");
    # §10108 / §71109 kept Cuban/Haitian entrants and COFA citizens (outside judge, 2026-10-28).
    for st in ["cuban_haitian_entrant", "cofa"] {
        p_st = dict(refugee, citizenship=st);
        check(status_rule("snap-rule", p_st)["status"] == "met", st + " keeps SNAP");
        check(status_rule("medicaid-rule", p_st)["status"] == "met", st + " keeps Medicaid");
    }
    recent = {"household_size": 1, "income_annual": 12000, "state": "IL", "flags": ["lpr_recent"], "age": 30, "citizenship": "eligible_immigrant"};
    check(status_rule("snap-rule", recent)["status"] == "unknown", "green card under 5 years: adult SNAP is not a plain yes");
    check(status_rule("snap-rule", dict(recent, flags=["lpr_recent", "children"]))["status"] == "met", "green card under 5 years: children are exempt");
    tps_parent = {"household_size": 3, "income_annual": 24000, "state": "TX", "flags": ["children", "citizen_children"], "age": 35, "citizenship": "non_citizen"};
    check(status_rule("chip-rule", tps_parent)["status"] == "met", "citizen children of a parent with no status can get CHIP");
    check(status_rule("medicaid-rule", dict(refugee, citizenship="citizen_or_lpr"))["status"] == "met", "'yes' to citizen-or-green-card meets Medicaid status");
    for (txt, want) in [("im not a citizen but i have a green card, been here 7 yrs, need medicaid", "eligible_immigrant"),
                        ("I am a Guatemalan citizen, I came 2 years ago, I need a doctor", "non_citizen"),
                        ("my son was born here but I don't have papers. we need food", "non_citizen"),
                        ("I'm Cuban, came on parole in 2023, need food stamps", "cuban_haitian_entrant"),
                        ("I don't have a green card yet, my husband does", "non_citizen"),
                        ("I lost my green card and need a replacement", "eligible_immigrant"),
                        ("I'm a senior citizen and need help with meals", "")] {
        check(parse_intake(txt)["citizenship"] == want, "status of: " + txt[:40]);
    }
    # Pregnancy: the expected child counts, and the state's pregnancy limit
    # applies (KFF Jan 2026; PolicyEngine US agrees for these three).
    preg_tx = {"household_size": 1, "income_annual": 30000, "state": "TX", "flags": ["pregnant"], "age": 25, "citizenship": "citizen"};
    lim_tx = income_limit("medicaid-rule", preg_tx);
    check(int(lim_tx["limit"]) >= 30000 and "203%" in str(lim_tx["label"]) + str(lim_tx["note"]), "pregnant, alone in Texas, $2,500/mo: under the 203% pregnancy limit for 2");
    check(int(income_limit("wic-rule", dict(preg_tx, income_annual=38400))["limit"]) >= 38400, "pregnant, alone, $3,200/mo: WIC counts her as 2");
    check(int(income_limit("medicaid-rule", dict(preg_tx, state="CA", income_annual=33000))["limit"]) >= 33000, "pregnant, alone in California, $2,750/mo: under 213% for 2");
    check(int(income_limit("medicaid-rule", dict(preg_tx, flags=[]))["limit"]) < 30000, "not pregnant: the adult limit still applies");
    senior_oh = {"household_size": 1, "income_annual": 22800, "state": "OH", "flags": ["senior", "unearned_income"], "age": 70, "citizenship": "citizen"};
    sr_oh = score_resource(SNAP_RES, SNAP_RES["eligibility"], senior_oh, "I'm 70 and need food stamps");
    check(not [c for c in sr_oh["criteria"] if c["key"] == "income" and (c["status"] == "unmet" or " is over " in str(c["detail"]))] and "re $" not in str(sr_oh.get("counterfactual", "")) and sr_oh["tier"] != "unlikely", "a 70-year-old over 130% isn't told she's over a gross test that doesn't apply");
    # A known income over a strict limit is "unlikely", not "possible" (F9).
    all_res = json.load(open("data/resources.json"))["resources"];
    by_rule = {r["eligibility"]["rule_id"]: r for r in all_res};
    rich1 = {"household_size": 1, "income_annual": 360000, "state": "OH", "flags": [], "age": 40, "citizenship": "citizen"};
    check(score_resource(by_rule["lsc-rule"], by_rule["lsc-rule"]["eligibility"], rich1, "I need a lawyer for a contract dispute")["tier"] == "unlikely", "$360,000 alone: legal aid is unlikely");
    ny4 = {"household_size": 4, "income_annual": 90000, "state": "NY", "flags": ["children"], "age": 40, "citizenship": "citizen"};
    check(score_resource(by_rule["medicaid-rule"], by_rule["medicaid-rule"]["eligibility"], ny4, "need health insurance")["tier"] == "unlikely", "$90,000 family of 4 in NY: adult Medicaid unlikely");
    near = dict(rich1, income_annual=24000);
    check(score_resource(by_rule["lsc-rule"], by_rule["lsc-rule"]["eligibility"], near, "I need a lawyer, eviction")["tier"] != "unlikely", "legal aid stays open up to 200% with expenses");
    check("lpr_recent" in parse_intake("I got my green card 2 years ago and need food stamps")["flags"], "green card 2 years ago is under the 5-year bar");
    check("lpr_recent" not in parse_intake("I have had my green card for 7 years, need food stamps")["flags"], "green card 7 years is past the bar");

    single = prof(1, 1000, "IL", [], 40);
    check("3 months in 3 years" in income_limit("snap-rule", single)["note"], "SNAP time limit shown to a single 40-year-old");
    check("3 months" not in income_limit("snap-rule", prof(3, 1000, "IL", ["children"], 35))["note"], "no SNAP time limit for a parent");
    check("3 months" not in income_limit("snap-rule", prof(1, 1000, "IL", ["senior"], 67))["note"], "no SNAP time limit at 67");
    check("3 months" in income_limit("snap-rule", prof(1, 1000, "IL", ["senior"], 62))["note"], "SNAP time limit now reaches 62");
    check("3 months" not in income_limit("snap-rule", prof(1, 1000, "IL", ["disabled"], 40))["note"], "no SNAP time limit with a disability");

    on("2026-10-01");
    mw = income_limit("medicaid-rule", single)["note"];
    check("From January 1, 2027" in mw and "80 hours" in mw, "Medicaid work requirement announced before 2027");
    on("2027-01-02");
    mw2 = income_limit("medicaid-rule", single)["note"];
    check(mw2.find("Adults 19–64") >= 0 and "From January" not in mw2, "Medicaid work requirement in force after Jan 1 2027");
    check("80 hours" not in income_limit("medicaid-rule", prof(3, 1000, "IL", ["children"], 35))["note"], "no Medicaid work note for a parent");
    check("80 hours" not in income_limit("medicaid-rule", prof(1, 1000, "IL", ["pregnant"], 28))["note"], "no Medicaid work note in pregnancy");

    # ---- 4. Coverage gap ----
    gap = income_limit("medicaid-rule", prof(1, 900, "TX", [], 40));
    check("100% of the poverty line" in str(gap.get("blocked", "")), "coverage gap names the 100% subsidy floor");
    check("Marketplace is the fallback" not in str(gap.get("blocked", "")), "Marketplace no longer called the fallback");

    # ---- 5. Per-state limits (tools/oracle_programs.py vs PolicyEngine US) ----
    check(abs(int(income_limit("medicaid-rule", prof(3, 1000, "TN", ["children"], 35))["limit"]) - int(round(fpl_annual(3, "TN") * 1.05))) <= 1, "Tennessee parents: 105% of poverty, not the old flat 40%");
    check(abs(int(income_limit("medicaid-rule", prof(3, 1000, "TX", ["children"], 35))["limit"]) - int(round(fpl_annual(3, "TX") * 0.15))) <= 1, "Texas parents: 15% of poverty");
    ny = income_limit("chip-rule", prof(3, 5000, "NY", ["children"], 35));
    check(abs(int(ny["limit"]) - int(round(fpl_annual(3, "NY") * 4.05))) <= 1 and not ny["typical"], "New York children: 405%, a state figure, not the typical one");
    check(bool(income_limit("chip-rule", prof(3, 5000, "", ["children"], 35))["typical"]), "unknown state keeps the typical CHIP figure, labelled as such");
    check(bool(income_limit("nslp-rule", prof(3, 9000, "CA", ["children"], 35)).get("none")), "California: school meals free at any income");
    check(int(income_limit("nslp-rule", prof(3, 9000, "TX", ["children"], 35)).get("limit", 0)) > 0, "Texas: school meals keep the income test");

    print("CivicMesh policy-date checks — " + str(total[0]) + " checks");
    for f in fails { print("  FAIL " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
