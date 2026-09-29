"""Effective-dated benefit policy — the numbers the eligibility engine uses.

Income limits are not flat dollar amounts: nearly every federal program is
defined as a percentage of the HHS poverty guideline (which grows with
household size and is higher in Alaska and Hawaii) or of HUD's area median
income. Immigrant eligibility changed in 2025–26 under Public Law 119-21
(the "One Big Beautiful Bill Act"). This module encodes those rules with
their effective dates and sources, so every explanation can cite them:

  "$24,000/yr is under 130% of the 2026 poverty line for a household of 3
   ($35,516) — HHS 2026 poverty guidelines"

Sources (checked 2026-09-29):
  * USDA SNAP FY2027 cost-of-living adjustments, memo of 2026-08-21
    (effective 2026-10-01): max allotments, standard deductions, minimum
    benefit. The FY2026 figures stay in force before that date.
  * P.L. 119-21 §10102 (SNAP time limit, implemented from late 2025): adults
    18–64 without a child under 14 get 3 months in 36 unless they work,
    volunteer or train 80 hours a month or are exempt.
  * P.L. 119-21 §71119 (Medicaid): expansion adults 19–64 must show 80 hours
    a month of work, school or volunteering (or $580/month in earnings) from
    January 1, 2027 at the latest, unless exempt.
  * HHS/ASPE 2026 poverty guidelines, Federal Register 2026-01-15:
    48 states + DC $15,960 + $5,680/person; AK $19,950 + $7,100; HI $18,360 + $6,530.
  * HUD FY2026 Section 8 income limits (effective 2026-05-01): U.S. median
    family income $107,900; size adjustments 70/80/90/100/108/116/124/132%.
  * KFF, Status of State Medicaid Expansion Decisions: 41 states incl. DC
    expanded; not expanded: AL FL GA KS MS SC TN TX WI WY (WI covers adults
    to 100% FPL without expansion).
  * P.L. 119-21 §10108 (SNAP, effective 2025-07-04) and §71109
    (Medicaid/CHIP, effective 2026-10-01): federally funded eligibility
    limited to citizens, nationals, green-card holders, Cuban/Haitian
    entrants and COFA citizens; refugees, asylees and parolees lose it.
    USDA/FNS memo 2025-12-09: the five-year bar and its exceptions unchanged.
  * Program thresholds: SNAP gross 130% FPL; WIC 185%; school meals free
    130% / reduced 185%; CSFP 150%; LIHEAP 150% FPL (or 60% state median);
    Medicaid expansion adults 138%; LSC civil legal aid 125%; Section 8
    50% AMI; public housing 80% AMI.
  Programs whose limits are set locally carry "typical": true and say so.
"""

import os;
import json;
import math;
import datetime;

glob POLICY_VERSION: str = "2026-09-29";

glob FPL_YEAR: int = 2026;
glob FPL: dict = {
    "default": [15960, 5680],
    "AK": [19950, 7100],
    "HI": [18360, 6530]
};
glob FPL_SOURCE: str = "HHS 2026 poverty guidelines";

glob HUD_MFI: int = 107900;
glob HUD_SIZE_ADJ: list = [0.70, 0.80, 0.90, 1.00, 1.08, 1.16, 1.24, 1.32];
# HUD's published limits for the metro area / county of each city the parser
# recognises (data/hud_income_limits.json, built by tools/build_hud_limits.py
# from Section8-FY26.xlsx). Limits are local: for a family of 4 the 50% limit
# is $50,300 in San Antonio and $105,050 in San Francisco, where the national
# formula above gives $53,950 (outside review, round 3).
glob HUD_LOCAL: dict = {};

"""Load the local HUD limits once."""
def hud_local -> dict {
    if HUD_LOCAL { return HUD_LOCAL; }
    for d in [os.path.join(os.getcwd(), "data"), os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data")] {
        f = os.path.join(d, "hud_income_limits.json");
        if os.path.exists(f) {
            HUD_LOCAL.update(json.load(open(f, encoding="utf-8")));
            break;
        }
    }
    return HUD_LOCAL;
}

"""HUD's published limit for this city's area at `pct` of median, or None."""
def local_ami(city: str, pct: float, household: int) -> dict {
    tab = hud_local();
    row = tab.get("cities", {}).get(str(city or "").strip().lower());
    if not row { return {}; }
    area = tab["areas"][row["area"]];
    col = "l50" if int(pct) == 50 else ("l80" if int(pct) == 80 else ("eli" if int(pct) == 30 else ""));
    n = max(1, int(household));
    if col {
        vals = list(area[col]);
        # Over 8 people: HUD adds 8% of the 4-person limit per extra person.
        lim = int(vals[n - 1]) if n <= 8 else int(vals[7]) + int(round(0.08 * int(vals[3]) * (n - 8)));
    } else {
        base = list(area["l50"]);
        lim = int(round((int(base[n - 1]) if n <= 8 else int(base[7])) * float(pct) / 50.0 / 50.0) * 50);
    }
    return {"limit": lim, "area": str(area["name"]).replace(" HUD Metro FMR Area", "").replace(" MSA", "")};
}
glob HUD_SOURCE: str = "HUD FY2026 income limits (U.S. median family income $107,900)";

glob MEDICAID_NOT_EXPANDED: list = ["AL", "FL", "GA", "KS", "MS", "SC", "TN", "TX", "WI", "WY"];
glob STATE_NAMES: dict = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
    "CT": "Connecticut", "DE": "Delaware", "DC": "the District of Columbia", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
    "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts",
    "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
    "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
    "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington",
    "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming", "GU": "Guam", "VI": "the U.S. Virgin Islands"
};

# SNAP gross-income limit by state, % of poverty (USDA FNS "Broad-Based
# Categorical Eligibility" chart, last updated June 2026). A household under
# its state's limit is categorically eligible: no net-income or asset test.
# States not listed (KS MO MS SD TN UT WY) use the federal 130% test. New York
# depends on the household (200% with dependent-care costs, 150% with
# earnings, else 130%); Arkansas is 165% only for elderly/disabled households.
glob SNAP_BBCE: dict = {
    "AL": 130, "AK": 200, "AZ": 200, "AR": 130, "CA": 200, "CO": 200, "CT": 200, "DE": 200, "DC": 200,
    "FL": 200, "GA": 130, "GU": 165, "HI": 200, "ID": 130, "IL": 165, "IN": 130, "IA": 160, "KY": 200,
    "LA": 200, "ME": 200, "MD": 200, "MA": 200, "MI": 200, "MN": 200, "MT": 200, "NE": 165, "NV": 200,
    "NH": 200, "NJ": 185, "NM": 200, "NY": 150, "NC": 200, "ND": 200, "OH": 130, "OK": 130, "OR": 200,
    "PA": 200, "RI": 185, "SC": 130, "TX": 165, "VT": 185, "VI": 175, "VA": 200, "WA": 200, "WV": 200,
    "WI": 200
};
glob SNAP_BBCE_SOURCE: str = "USDA FNS broad-based categorical eligibility chart (June 2026)";
# States whose categorical-eligibility program keeps the net-income test
# (California: LA County CalFresh manual, MCE 200/130; the others as compiled
# from state manuals in PolicyEngine US). The second list is for households
# with someone elderly or disabled. Found by tools/oracle_policyengine.py.
glob SNAP_BBCE_NET_TEST: list = ["CA", "HI", "IN", "LA", "ND", "RI"];
glob SNAP_BBCE_NET_TEST_ED: list = ["AL", "CA", "HI", "ID", "IN", "LA", "MN", "ND", "NE", "OK", "RI"];
# State-funded minimum benefits: New Jersey $95 for every SNAP household,
# D.C. $30; Maryland $40 when someone is 62 or older.
glob SNAP_STATE_MIN: dict = {"NJ": 95, "DC": 30};
glob SNAP_MD_SENIOR_MIN: int = 40;

"""SNAP gross-income limit (% of poverty) for this household's state, and a
sentence saying where it comes from. Unknown state: the federal 130%."""
def snap_gross_pct(profile: dict) -> tuple {
    state = str(profile.get("state", "") or "").upper();
    flags = list(profile.get("flags", []));
    if not state {
        return (130, "federal 130% test; most states go higher (up to 200%) — tell me your state");
    }
    name = str(STATE_NAMES.get(state, state));
    pct = int(SNAP_BBCE.get(state, 130));
    if state == "AR" and ("senior" in flags or "disabled" in flags) { pct = 165; }
    if state == "NY" and "unearned_income" in flags { pct = 130; }
    if state not in SNAP_BBCE {
        return (130, name + " uses the federal 130% gross-income test");
    }
    if pct <= 130 {
        return (130, name + " keeps the 130% gross-income test");
    }
    extra = " (200% with child- or dependent-care costs)" if state == "NY" else "";
    after = "; the net-income test still applies" if state in SNAP_BBCE_NET_TEST else "; under it there's no net-income or asset test";
    return (pct, name + " raises the gross-income limit to " + str(pct) + "% of poverty" + extra + after);
}

glob OBBBA_SNAP_DATE: str = "2025-07-04";
glob OBBBA_MEDICAID_DATE: str = "2026-10-01";
glob MEDICAID_WORK_DATE: str = "2027-01-01";

# rule_id → income basis + immigrant-status rule.
#   income: {basis: fpl|ami|medicaid|none, pct, note, typical}
#   status: snap | medicaid | hud | lsc | "" (no status test)
glob PROGRAMS: dict = {
    "section8-hcv-rule":     {"income": {"basis": "ami", "pct": 50, "note": "75% of new vouchers go to households under 30% of area median"}, "status": "hud"},
    "esg-shelter-rule":      {"income": {"basis": "none"}, "status": ""},
    "rrh-rule":              {"income": {"basis": "ami", "pct": 30, "note": "ESG-funded rapid re-housing re-checks income against 30% of area median"}, "status": ""},
    "liheap-rule":           {"income": {"basis": "fpl", "pct": 150, "note": "states may use 60% of state median income instead, if higher"}, "status": ""},
    "public-housing-rule":   {"income": {"basis": "ami", "pct": 80}, "status": "hud"},
    "ndv-shelter-rule":      {"income": {"basis": "none"}, "status": ""},
    "coc-psh-rule":          {"income": {"basis": "none"}, "status": ""},
    "hud-vash-rule":         {"income": {"basis": "ami", "pct": 50, "note": "PHAs may admit HUD-VASH families up to 80% of area median"}, "status": "hud"},
    "salvation-army-th-rule": {"income": {"basis": "none", "note": "income rules vary by site"}, "status": ""},
    "cc-era-rule":           {"income": {"basis": "ami", "pct": 80, "typical": True, "note": "typical for emergency rental assistance; varies by diocese"}, "status": ""},
    "snap-rule":             {"income": {"basis": "fpl", "pct": 130, "note": "gross test; the state's limit replaces 130% (snap_gross_pct)"}, "status": "snap"},
    "wic-rule":              {"income": {"basis": "fpl", "pct": 185, "note": "automatically income-eligible if on SNAP, Medicaid or TANF"}, "status": ""},
    "feeding-america-rule":  {"income": {"basis": "none"}, "status": ""},
    "nslp-rule":             {"income": {"basis": "fpl", "pct": 185, "note": "free meals under 130%, reduced-price under 185%; community-eligibility schools serve everyone free"}, "status": ""},
    "mow-rule":              {"income": {"basis": "none"}, "status": ""},
    "tefap-rule":            {"income": {"basis": "fpl", "pct": 185, "typical": True, "note": "each state sets the TEFAP limit, commonly 185–300%"}, "status": ""},
    "sfsp-rule":             {"income": {"basis": "none"}, "status": "", "season": [6, 8], "season_note": "Summer meal sites run June–August; during the school year, school meals and food banks cover the same need"},
    "sfmnp-rule":            {"income": {"basis": "fpl", "pct": 185}, "status": ""},
    "fridge-rule":           {"income": {"basis": "none"}, "status": ""},
    "csfp-rule":             {"income": {"basis": "fpl", "pct": 150}, "status": ""},
    "medicaid-rule":         {"income": {"basis": "medicaid", "pct": 138}, "status": "medicaid"},
    "chip-rule":             {"income": {"basis": "fpl", "pct": 255, "typical": True, "note": "state-set, from about 170% to 400%; 255% is the national median"}, "status": "medicaid"},
    "fqhc-rule":             {"income": {"basis": "none", "note": "sliding-scale discounts below 200% of poverty; no one is turned away for inability to pay"}, "status": ""},
    "988-rule":              {"income": {"basis": "none"}, "status": ""},
    "samhsa-rule":           {"income": {"basis": "none"}, "status": ""},
    "ryan-white-rule":       {"income": {"basis": "fpl", "pct": 400, "typical": True, "note": "states set 300–500%"}, "status": ""},
    "needymeds-rule":        {"income": {"basis": "none"}, "status": ""},
    "dental-clinic-rule":    {"income": {"basis": "fpl", "pct": 200, "typical": True, "note": "typical for charitable clinics; varies"}, "status": ""},
    "eyecare-america-rule":  {"income": {"basis": "none"}, "status": ""},
    "cmhc-rule":             {"income": {"basis": "none", "note": "sliding-scale fees"}, "status": ""},
    "lsc-rule":              {"income": {"basis": "fpl", "pct": 125, "note": "up to 200% with allowable expenses"}, "status": "lsc"},
    "imm-legal-rule":        {"income": {"basis": "none"}, "status": ""},
    "pd-rule":               {"income": {"basis": "fpl", "pct": 125, "typical": True, "note": "indigency standards vary by county"}, "status": ""},
    "tenant-rights-rule":    {"income": {"basis": "none"}, "status": ""},
    "dv-legal-rule":         {"income": {"basis": "none"}, "status": ""},
    "dr-rule":               {"income": {"basis": "none"}, "status": ""},
    "cfpb-rule":             {"income": {"basis": "none"}, "status": ""},
    "expungement-rule":      {"income": {"basis": "fpl", "pct": 200, "typical": True, "note": "varies by clinic"}, "status": ""},
    "aba-fla-rule":          {"income": {"basis": "fpl", "pct": 250, "typical": True, "note": "each state sets the limit"}, "status": ""},
    "law-clinic-rule":       {"income": {"basis": "fpl", "pct": 200, "typical": True, "note": "varies by clinic"}, "status": ""}
};

"""Today's date for effective-dated rules (CIVICMESH_POLICY_DATE=YYYY-MM-DD overrides, for tests)."""
def policy_today -> str {
    forced = str(os.environ.get("CIVICMESH_POLICY_DATE", "")).strip();
    return forced if forced else datetime.date.today().isoformat();
}

glob SNAP_TIME_LIMIT_NOTE: str = "Time limit: adults 18–64 without a child under 14 at home may get SNAP for only 3 months in 3 years unless they work, volunteer or train 80 hours a month or are exempt, e.g. unable to work or pregnant (P.L. 119-21 §10102; the SNAP office decides exemptions)";

"""Medicaid work-requirement note, effective-dated (P.L. 119-21 §71119)."""
def medicaid_work_note -> str {
    rule = "adults 19–64 covered through the expansion must show 80 hours a month of work, school or volunteering (or $580/month in earnings) unless exempt, e.g. parents of a child 13 or younger, pregnant or medically frail (P.L. 119-21 §71119)";
    if policy_today() < MEDICAID_WORK_DATE {
        return "From January 1, 2027 at the latest, " + rule + "; some states start earlier";
    }
    return rule[0].upper() + rule[1:];
}

"""Whether a work rule's note should be shown: an adult of working age with
no exemption the conversation has revealed. Only decides a note, never a tier.
"""
def _work_rule_applies(profile: dict, lo: int) -> bool {
    flags = list(profile.get("flags", []));
    if "children" in flags or "pregnant" in flags or "disabled" in flags {
        return False;
    }
    age = int(profile.get("age", 0) or 0);
    if age > 0 {
        return lo <= age and age <= 64;
    }
    # "Retired" or "elderly" with no age given: most people who say so are 65+.
    return "senior" not in flags;
}

"""HHS poverty guideline for a household size and state."""
def fpl_annual(household: int, state: str = "") -> int {
    row = FPL.get(str(state or "").upper(), FPL["default"]);
    n = max(1, int(household));
    return int(row[0]) + int(row[1]) * (n - 1);
}

"""HUD income limit at `pct` of median for a household size (national median; rounded up to $50)."""
def ami_limit(pct: float, household: int) -> int {
    n = max(1, int(household));
    adj = HUD_SIZE_ADJ[n - 1] if n <= 8 else 1.32 + 0.08 * (n - 8);
    raw = HUD_MFI * (float(pct) / 100.0) * adj;
    return int(math.ceil(raw / 50.0) * 50);
}

"""Resolve a program's income limit for this profile.

Returns {} when the program has no income test, else
{limit, label, per_person, assumed_household, source, note, typical, blocked}.
`blocked` is a reason string when the rule itself excludes the person (e.g.
childless adults in a state that did not expand Medicaid).
"""
def income_limit(rule_id: str, profile: dict, flat_fallback: int = 0) -> dict {
    pol = PROGRAMS.get(str(rule_id));
    if not pol {
        if flat_fallback > 0 {
            return {"limit": flat_fallback, "label": "the program's " + "$" + f"{flat_fallback:,}" + " limit", "per_person": 0, "assumed_household": False, "source": "catalog", "note": "", "typical": True, "blocked": ""};
        }
        return {};
    }
    inc = pol["income"];
    basis = str(inc.get("basis", "none"));
    if basis == "none" {
        return {"none": True, "note": str(inc.get("note", ""))};
    }
    hh = int(profile.get("household_size", 0) or 0);
    assumed = hh <= 0;
    n = 1 if assumed else hh;
    state = str(profile.get("state", "") or "").upper();
    pct = float(inc.get("pct", 100));
    note = str(inc.get("note", ""));
    blocked = "";
    who = "a household of " + str(n);
    if basis == "ami" {
        loc = local_ami(str(profile.get("city", "")), pct, n);
        if loc {
            limit = int(loc["limit"]);
            per = int(local_ami(str(profile.get("city", "")), pct, n + 1)["limit"]) - limit;
            label = str(int(pct)) + "% of area median income for " + who + " in the " + str(loc["area"]) + " area";
            source = "HUD FY2026 Section 8 income limits, " + str(loc["area"]);
        } else {
            limit = ami_limit(pct, n);
            per = ami_limit(pct, n + 1) - limit;
            label = str(int(pct)) + "% of area median income for " + who + " (national estimate)";
            source = HUD_SOURCE;
            note = (note + "; " if note else "") + "HUD sets this limit by county or metro area; tell me your city for the exact figure";
        }
    } else {
        if basis == "medicaid" {
            flags = list(profile.get("flags", []));
            has_kids = "children" in flags or "pregnant" in flags or n >= 2 and "family" in flags;
            covered_group = "pregnant" in flags or "senior" in flags or "disabled" in flags;
            if state in MEDICAID_NOT_EXPANDED and not covered_group {
                sname = str(STATE_NAMES.get(state, state));
                if state == "WI" {
                    pct = 100.0;
                    note = "Wisconsin covers adults up to 100% of poverty without the ACA expansion";
                } elif has_kids {
                    pct = 40.0;
                    note = sname + " did not expand Medicaid: parents qualify only at very low incomes (often under 40% of poverty), but children usually qualify through Medicaid or CHIP";
                } else {
                    blocked = sname + " did not expand Medicaid, so adults without children, a disability or a pregnancy generally can't get it at any income. ACA Marketplace subsidies start at 100% of the poverty line; below that, a community health center (sliding-scale fees) is the fallback";
                    note = blocked;
                }
            } else {
                note = "ACA expansion adults; children and pregnant women qualify at higher incomes";
                if _work_rule_applies(profile, 19) {
                    note = note + ". " + medicaid_work_note();
                }
            }
        }
        if str(rule_id) == "snap-rule" {
            (spct, snote) = snap_gross_pct(profile);
            pct = float(spct);
            note = snote + "; a household with someone 60+ or disabled skips the gross test (the net test still applies)";
            if _work_rule_applies(profile, 18) {
                note = note + ". " + SNAP_TIME_LIMIT_NOTE;
            }
        }
        limit = int(round(fpl_annual(n, state) * pct / 100.0));
        per = int(round(fpl_annual(n + 1, state) * pct / 100.0)) - limit;
        label = str(int(pct)) + "% of the " + str(FPL_YEAR) + " poverty line for " + who;
        source = FPL_SOURCE + (" (" + str(STATE_NAMES.get(state, state)) + " table)" if state in ["AK", "HI"] else "") + ("; " + SNAP_BBCE_SOURCE if str(rule_id) == "snap-rule" else "");
    }
    return {
        "limit": limit, "label": label, "per_person": per, "assumed_household": assumed,
        "source": source, "note": note, "typical": bool(inc.get("typical", False)), "blocked": blocked
    };
}

"""Immigrant-status test for a program, effective-dated.

status: citizen | eligible_immigrant (green card / LPR) | humanitarian
(refugee, asylee, parolee) | non_citizen | "" (unknown).
Returns {} when the program has no status test, else
{status: met|unmet|unknown, detail, change_note}.
"""
def status_rule(rule_id: str, profile: dict) -> dict {
    pol = PROGRAMS.get(str(rule_id));
    if not pol or not pol.get("status") {
        return {};
    }
    kind = str(pol["status"]);
    st = str(profile.get("citizenship", "") or "");
    today = policy_today();
    flags = list(profile.get("flags", []));
    kids = "children" in flags or "pregnant" in flags;
    if not st {
        return {"status": "unknown", "detail": "Citizens, green-card holders and some other statuses qualify", "change_note": ""};
    }
    if st == "citizen" {
        return {"status": "met", "detail": "U.S. citizen", "change_note": ""};
    }
    if kind == "hud" {
        if st in ["eligible_immigrant", "humanitarian"] {
            return {"status": "met", "detail": "Green card, refugee and asylee status qualify for HUD programs", "change_note": ""};
        }
        return {"status": "unmet", "detail": "Needs an eligible immigration status; mixed-status families get prorated help", "change_note": ""};
    }
    if kind == "lsc" {
        if st in ["eligible_immigrant", "humanitarian"] or "dv" in flags {
            return {"status": "met", "detail": "LSC-funded offices can serve green-card holders, refugees, asylees and survivors of domestic violence", "change_note": ""};
        }
        return {"status": "unmet", "detail": "LSC-funded offices generally can't represent people without an eligible status (survivors of violence excepted)", "change_note": ""};
    }
    wait_note = " (adults may face a 5-year wait after getting the green card" + ("; children are exempt" if kind == "snap" else "") + ")";
    if kind == "snap" {
        if st == "eligible_immigrant" {
            return {"status": "met", "detail": "Green-card holders qualify" + wait_note, "change_note": ""};
        }
        if st == "humanitarian" {
            return {"status": "unmet", "detail": "Since July 4, 2025 (P.L. 119-21 §10108) refugees, asylees and parolees are no longer eligible for SNAP; after getting a green card they are again, with no 5-year wait", "change_note": ""};
        }
        return {"status": "unmet", "detail": "SNAP requires citizenship or a green card" + ("; U.S.-citizen children in the household can still get it" if kids else ""), "change_note": ""};
    }
    if kind == "medicaid" {
        if st == "eligible_immigrant" {
            return {"status": "met", "detail": "Green-card holders qualify" + wait_note, "change_note": ""};
        }
        if st == "humanitarian" {
            if today < OBBBA_MEDICAID_DATE {
                return {"status": "met", "detail": "Refugees and asylees qualify until September 30, 2026", "change_note": "From October 1, 2026 (P.L. 119-21 §71109) federally funded Medicaid/CHIP ends for refugees, asylees and parolees who don't have a green card"};
            }
            return {"status": "unmet", "detail": "Since October 1, 2026 (P.L. 119-21 §71109) refugees, asylees and parolees without a green card can't get federally funded Medicaid/CHIP; some states cover them with state funds", "change_note": ""};
        }
        return {"status": "unmet", "detail": "Only emergency Medicaid is available without an eligible status" + ("; U.S.-citizen children can still enroll" if kids else ""), "change_note": ""};
    }
    return {};
}

"""Short provenance line for the UI."""
def policy_sources -> list {
    return [FPL_SOURCE + " (effective Jan 15, 2026)", HUD_SOURCE + " (effective May 1, 2026)", "USDA SNAP " + str(snap_year()["fy"]) + " allotments (from " + str(snap_year()["from"]) + ")", "KFF state Medicaid expansion status (2026)", "P.L. 119-21 §10108 SNAP (Jul 4, 2025) · §71109 Medicaid/CHIP (Oct 1, 2026)"];
}

# ---------- SNAP benefit estimate ----------
# USDA's cost-of-living adjustments take effect every October 1. Each year:
# max allotment for 1–8 people + each extra person; standard deduction for
# 1–2, 3, 4, 5, 6+ people; the minimum benefit for 1–2 person households;
# the 18+ person cap (200% of the 4-person max over the 8-person max).
# FY2027: USDA memo of 2026-08-21. FY2026 kept so earlier dates reproduce.
# Alaska is the urban column.
glob SNAP_YEARS: list = [
    {
        "fy": "FY2027", "from": "2026-10-01",
        "max": {
            "default": [306, 562, 808, 1023, 1217, 1463, 1616, 1841, 225],
            "AK": [392, 718, 1032, 1306, 1555, 1868, 2064, 2352, 287],
            "HI": [496, 910, 1307, 1655, 1969, 2367, 2615, 2979, 364]
        },
        "std": {
            "default": [217, 217, 217, 229, 268, 308],
            "AK": [371, 371, 371, 371, 371, 385],
            "HI": [306, 306, 306, 306, 309, 354]
        },
        "min": {"default": 25, "AK": 31, "HI": 40},
        "cap18": {"default": 3887, "AK": 4965, "HI": 6289}
    },
    {
        "fy": "FY2026", "from": "2025-10-01",
        "max": {
            "default": [298, 546, 785, 994, 1183, 1421, 1571, 1789, 218],
            "AK": [385, 707, 1015, 1285, 1529, 1838, 2031, 2314, 282],
            "HI": [506, 929, 1334, 1689, 2010, 2415, 2668, 3040, 371]
        },
        "std": {
            "default": [209, 209, 209, 223, 261, 299],
            "AK": [358, 358, 358, 358, 358, 374],
            "HI": [295, 295, 295, 295, 300, 344]
        },
        "min": {"default": 24, "AK": 31, "HI": 40},
        "cap18": {}
    }
];

"""The SNAP parameter year in force on the policy date."""
def snap_year -> dict {
    today = policy_today();
    for y in SNAP_YEARS {
        if today >= str(y["from"]) { return y; }
    }
    return SNAP_YEARS[-1];
}

"""Estimated monthly SNAP benefit: max allotment − 30% of net income.

Net income = gross − 20% earned-income deduction (earnings only, so not for
Social Security, SSI or a pension) − standard deduction. USDA's formula
without the shelter, dependent-care and medical deductions, so rent,
childcare and a senior's medical costs usually raise it. Every household
must pass the net test (100% of poverty); only elderly or disabled
households skip the gross test (130%). Returns {} when income is unknown or
the household fails a test.
"""
def snap_estimate(profile: dict) -> dict {
    income = int(profile.get("income_annual", -1));
    if income < 0 {
        return {};
    }
    hh = int(profile.get("household_size", 0) or 0);
    assumed = hh <= 0;
    n = 1 if assumed else hh;
    state = str(profile.get("state", "") or "").upper();
    flags = list(profile.get("flags", []));
    elderly_disabled = "senior" in flags or "disabled" in flags;
    earned = "unearned_income" not in flags;
    gross = income / 12.0;
    (gpct, _gnote) = snap_gross_pct(profile);
    # Under the state's limit a household is categorically eligible (broad-
    # based categorical eligibility): no net test. Over it, only an elderly
    # or disabled household can still qualify, through the net test.
    categorical = state in SNAP_BBCE and gross <= fpl_annual(n, state) * gpct / 100.0 / 12.0;
    if state in (SNAP_BBCE_NET_TEST_ED if elderly_disabled else SNAP_BBCE_NET_TEST) {
        categorical = False;
    }
    if gross > fpl_annual(n, state) * max(1.30, gpct / 100.0) / 12.0 and not elderly_disabled {
        return {};
    }
    y = snap_year();
    region = state if state in ["AK", "HI"] else "default";
    mx = list(y["max"][region]);
    if n <= 8 {
        maxa = int(mx[n - 1]);
    } else {
        cap = int(y["cap18"].get(region, int(mx[7]) + 2 * int(mx[3])));
        maxa = min(int(mx[7]) + int(mx[8]) * (n - 8), cap);
    }
    sd = int(list(y["std"][region])[min(n, 6) - 1]);
    net = max(0.0, gross * (0.8 if earned else 1.0) - sd);
    if net > fpl_annual(n, state) / 12.0 and not categorical {
        return {};
    }
    ben = int(round(maxa - 0.3 * net));
    if n <= 2 {
        ben = max(ben, int(y["min"][region]));
    }
    if state in SNAP_STATE_MIN {
        ben = max(ben, int(SNAP_STATE_MIN[state]));
    }
    age = int(profile.get("age", 0) or 0);
    if state == "MD" and (age >= 62 or (age == 0 and "senior" in flags)) {
        ben = max(ben, SNAP_MD_SENIOR_MIN);
    }
    if ben <= 0 {
        return {};
    }
    deds = ("the 20% earnings and $" + str(sd) + " standard deductions") if earned else ("the $" + str(sd) + " standard deduction; no earnings deduction for Social Security, SSI or pension income");
    raises = "Rent, childcare and medical costs usually raise it." if elderly_disabled else "Rent and childcare deductions usually raise it.";
    return {
        "monthly": ben, "max": maxa, "household": n, "assumed_household": assumed,
        "label": "≈ $" + f"{ben:,}" + "/mo",
        "basis": "USDA " + str(y["fy"]) + ": max $" + f"{maxa:,}" + " for " + str(n) + " − 30% of net income ($" + f"{int(net):,}" + "/mo after " + deds + "). " + raises,
        "source": "USDA SNAP " + str(y["fy"]) + " maximum allotments and deductions (from " + str(y["from"]) + ")"
    };
}

"""Seasonal programs: {} when always open, else {open, detail}."""
def season_rule(rule_id: str) -> dict {
    pol = PROGRAMS.get(str(rule_id));
    if not pol or not pol.get("season") {
        return {};
    }
    month = int(policy_today()[5:7]);
    lo = int(pol["season"][0]);
    hi = int(pol["season"][1]);
    return {"open": lo <= month and month <= hi, "detail": str(pol.get("season_note", ""))};
}
