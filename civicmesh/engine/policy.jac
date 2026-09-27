"""Effective-dated benefit policy — the numbers the eligibility engine uses.

Income limits are not flat dollar amounts: nearly every federal program is
defined as a percentage of the HHS poverty guideline (which grows with
household size and is higher in Alaska and Hawaii) or of HUD's area median
income. Immigrant eligibility changed in 2025–26 under Public Law 119-21
(the "One Big Beautiful Bill Act"). This module encodes those rules with
their effective dates and sources, so every explanation can cite them:

  "$24,000/yr is under 130% of the 2026 poverty line for a household of 3
   ($35,516) — HHS 2026 poverty guidelines"

Sources (checked 2026-09-27):
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
import math;
import datetime;

glob POLICY_VERSION: str = "2026-09-27";

glob FPL_YEAR: int = 2026;
glob FPL: dict = {
    "default": [15960, 5680],
    "AK": [19950, 7100],
    "HI": [18360, 6530]
};
glob FPL_SOURCE: str = "HHS 2026 poverty guidelines";

glob HUD_MFI: int = 107900;
glob HUD_SIZE_ADJ: list = [0.70, 0.80, 0.90, 1.00, 1.08, 1.16, 1.24, 1.32];
glob HUD_SOURCE: str = "HUD FY2026 income limits (U.S. median family income $107,900)";

glob MEDICAID_NOT_EXPANDED: list = ["AL", "FL", "GA", "KS", "MS", "SC", "TN", "TX", "WI", "WY"];
glob STATE_NAMES: dict = {
    "AL": "Alabama", "FL": "Florida", "GA": "Georgia", "KS": "Kansas", "MS": "Mississippi",
    "SC": "South Carolina", "TN": "Tennessee", "TX": "Texas", "WI": "Wisconsin", "WY": "Wyoming",
    "AK": "Alaska", "HI": "Hawaii"
};

glob OBBBA_SNAP_DATE: str = "2025-07-04";
glob OBBBA_MEDICAID_DATE: str = "2026-10-01";

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
    "snap-rule":             {"income": {"basis": "fpl", "pct": 130, "note": "gross test; many states allow up to 200% (broad-based categorical eligibility); no gross test for elderly/disabled households"}, "status": "snap"},
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
        limit = ami_limit(pct, n);
        per = ami_limit(pct, n + 1) - limit;
        label = str(int(pct)) + "% of area median income for " + who;
        source = HUD_SOURCE;
        note = (note + "; " if note else "") + "your local housing authority's limit may differ";
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
                    blocked = sname + " did not expand Medicaid, so adults without children, a disability or a pregnancy generally can't get it at any income — a community health center or the ACA Marketplace is the fallback";
                    note = blocked;
                }
            } else {
                note = "ACA expansion adults; children and pregnant women qualify at higher incomes";
            }
        }
        limit = int(round(fpl_annual(n, state) * pct / 100.0));
        per = int(round(fpl_annual(n + 1, state) * pct / 100.0)) - limit;
        label = str(int(pct)) + "% of the " + str(FPL_YEAR) + " poverty line for " + who;
        source = FPL_SOURCE + (" (" + str(STATE_NAMES.get(state, state)) + " table)" if state in ["AK", "HI"] else "");
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
    return [FPL_SOURCE + " (effective Jan 15, 2026)", HUD_SOURCE + " (effective May 1, 2026)", "KFF state Medicaid expansion status (2026)", "P.L. 119-21 §10108 SNAP (Jul 4, 2025) · §71109 Medicaid/CHIP (Oct 1, 2026)"];
}

# ---------- SNAP benefit estimate (USDA FNS, FY2026: Oct 1 2025 – Sep 30 2026) ----------
glob SNAP_FY: str = "FY2026";
glob SNAP_MAX: dict = {
    "default": [298, 546, 785, 994, 1183, 1421, 1571, 1789, 218],
    "AK": [385, 707, 1015, 1285, 1529, 1838, 2031, 2314, 282],
    "HI": [506, 929, 1334, 1689, 2010, 2415, 2668, 3040, 371]
};
glob SNAP_STD_DED: dict = {
    "default": [209, 209, 209, 223, 261, 299],
    "AK": [358, 358, 358, 358, 358, 374],
    "HI": [295, 295, 295, 295, 300, 344]
};

"""Estimated monthly SNAP benefit: max allotment − 30% of net income.

Net income = gross − 20% earned-income deduction − standard deduction
(USDA's formula without the shelter / dependent-care deductions, so the
estimate is conservative: rent and childcare usually raise it). Returns {}
when income or eligibility is unknown or over the gross limit.
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
    gross = income / 12.0;
    gross_limit = fpl_annual(n, state) * 1.30 / 12.0;
    if gross > gross_limit and not ("senior" in flags or "disabled" in flags) {
        return {};
    }
    mx = SNAP_MAX.get(state, SNAP_MAX["default"]);
    maxa = int(mx[n - 1]) if n <= 8 else int(mx[7]) + int(mx[8]) * (n - 8);
    ded = SNAP_STD_DED.get(state, SNAP_STD_DED["default"]);
    sd = int(ded[min(n, 6) - 1]);
    net = max(0.0, gross * 0.8 - sd);
    ben = int(round(maxa - 0.3 * net));
    if n <= 2 {
        ben = max(ben, int(round(int(mx[0]) * 0.08)));
    }
    if ben <= 0 {
        return {};
    }
    return {
        "monthly": ben, "max": maxa, "household": n, "assumed_household": assumed,
        "label": "≈ $" + f"{ben:,}" + "/mo",
        "basis": "USDA " + SNAP_FY + ": max $" + f"{maxa:,}" + " for " + str(n) + " − 30% of net income ($" + f"{int(net):,}" + "/mo after the 20% earnings and $" + str(sd) + " standard deductions). Rent and childcare deductions usually raise it.",
        "source": "USDA FNS SNAP " + SNAP_FY + " maximum allotments and deductions"
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
