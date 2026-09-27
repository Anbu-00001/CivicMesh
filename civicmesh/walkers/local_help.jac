"""LocalHelpWalker — real local offices from federal open data, off the critical path.

The seeded catalog is national ("your local housing authority"); this walker
turns that into names and phone numbers near the user by querying public,
keyless ArcGIS feature services:

  housing      HUD Public Housing Authorities (3,776 PHAs: phone, email,
               address, Section 8 voucher count) — HUD eGIS open data
  housing /    HUD-approved Housing Counseling Agencies (4,767 agencies:
  legal        eviction, foreclosure and rental counseling)
  healthcare   HRSA Health Center Service Delivery Sites (active sites,
               sliding-fee primary care; homeless-program flag)

Called by the client after the answer is on screen (like the narration), so
network latency never blocks a turn. Queries run in parallel with a 4 s
timeout each and results are cached per (category, place) for 6 hours.
City strings are reduced to letters, spaces and . ' - before being placed
in the SQL-like `where` clause.
"""

import re;
import json;
import time;
import urllib.parse;
import urllib.request;
import concurrent.futures;
import from engine.parse { STATES }

glob HUD_PHA: str = "https://services.arcgis.com/VTyQ9soqVukalItT/arcgis/rest/services/Public_Housing_Authorities/FeatureServer/0/query";
glob HUD_HCA: str = "https://services.arcgis.com/VTyQ9soqVukalItT/arcgis/rest/services/Housing_Counseling_Agencies_UAUC/FeatureServer/0/query";
glob HRSA_HC: str = "https://gisportal.hrsa.gov/server/rest/services/HealthCareFacilities/PrimaryHealthCareFacilities_FS/MapServer/0/query";
glob LOCAL_CACHE: dict = {};
glob CACHE_TTL_S: float = 21600.0;
glob HTTP_TIMEOUT_S: float = 4.0;
glob POOL: Any = concurrent.futures.ThreadPoolExecutor(max_workers=6, thread_name_prefix="cm-local");

"""State code → full name (HUD's counseling dataset stores names)."""
def state_name(code: str) -> str {
    for (name, st) in STATES.items() {
        if st == code { return str(name).title(); }
    }
    return "";
}

"""Run one ArcGIS query; returns the attribute dicts (empty on any error)."""
def arcgis(url: str, where: str, fields: str, order: str, n: int) -> list {
    q = urllib.parse.urlencode({"where": where, "outFields": fields, "orderByFields": order, "returnGeometry": "false", "resultRecordCount": str(n), "f": "json"});
    req = urllib.request.Request(url + "?" + q, headers={"User-Agent": "CivicMesh/2 (civic-aid navigator)"});
    with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as r {
        data = json.loads(r.read());
    }
    return [f["attributes"] for f in list(data.get("features", []))];
}

"""Format a 10-digit phone as 713-260-0500; pass anything else through."""
def fmt_phone(p: str) -> str {
    d = re.sub(r"\D", "", str(p or ""));
    if len(d) == 10 { return d[:3] + "-" + d[3:6] + "-" + d[6:]; }
    return str(p or "").strip();
}

def _clean(s: Any) -> str {
    return re.sub(r"\s+", " ", str(s or "")).strip();
}

"""Housing authorities: city match first, else the largest in the state."""
def phas(city: str, st: str) -> list {
    fields = "FORMAL_PARTICIPANT_NAME,HA_PHN_NUM,HA_EMAIL_ADDR_TEXT,STD_ADDR,STD_CITY,STD_ST,STD_ZIP5,SECTION8_UNITS_CNT,TOTAL_UNITS,HA_PROGRAM_TYPE";
    rows: list = [];
    if city {
        rows = arcgis(HUD_PHA, "STD_ST='" + st + "' AND UPPER(STD_CITY)='" + city.upper() + "'", fields, "SECTION8_UNITS_CNT DESC", 3);
    }
    if not rows {
        rows = arcgis(HUD_PHA, "STD_ST='" + st + "'", fields, "SECTION8_UNITS_CNT DESC", 3);
    }
    return [{
        "name": _clean(r["FORMAL_PARTICIPANT_NAME"]), "phone": fmt_phone(r["HA_PHN_NUM"]), "email": _clean(r["HA_EMAIL_ADDR_TEXT"]).lower(),
        "address": _clean(r["STD_ADDR"]) + ", " + _clean(r["STD_CITY"]) + ", " + _clean(r["STD_ST"]) + " " + _clean(r["STD_ZIP5"]),
        "detail": _clean(r["HA_PROGRAM_TYPE"]) + " · " + f"{int(r['SECTION8_UNITS_CNT'] or 0):,}" + " vouchers" + (" · " + f"{int(r['TOTAL_UNITS'] or 0):,}" + " public housing units" if int(r["TOTAL_UNITS"] or 0) > 0 else ""),
        "kind": "Public housing authority", "for": ["Section 8 Housing Choice Voucher Program", "Public Housing (HUD)", "HUD-VASH (Veterans Affairs Supportive Housing)"],
        "source": "HUD Public Housing Authorities (HUD eGIS open data)"
    } for r in rows];
}

"""HUD-approved housing counselors in the city (or state)."""
def counselors(city: str, st: str) -> list {
    sname = state_name(st);
    if not sname { return []; }
    fields = "AGC_NAME,AGC_PHONE_NBR,AGC_WEB_SITE,AGC_ADDRESS,AGC_CITY,AGC_STATE,AGC_ZIP_CODE";
    rows: list = [];
    if city {
        rows = arcgis(HUD_HCA, "AGC_STATE='" + sname + "' AND UPPER(AGC_CITY)='" + city.upper() + "'", fields, "AGC_NAME", 2);
    }
    if not rows {
        rows = arcgis(HUD_HCA, "AGC_STATE='" + sname + "'", fields, "AGC_NAME", 2);
    }
    return [{
        "name": _clean(r["AGC_NAME"]).title(), "phone": fmt_phone(r["AGC_PHONE_NBR"]), "url": _clean(r["AGC_WEB_SITE"]),
        "address": _clean(r["AGC_ADDRESS"]) + ", " + _clean(r["AGC_CITY"]) + ", " + st + " " + _clean(r["AGC_ZIP_CODE"])[:5],
        "detail": "HUD-approved counseling: eviction, rental, foreclosure",
        "kind": "Housing counselor", "for": ["Tenant Rights Hotline (National Housing Law Project)", "Catholic Charities Emergency Rental Assistance"],
        "source": "HUD Housing Counseling Agencies (HUD eGIS open data)"
    } for r in rows];
}

"""Active HRSA health center sites, longest opening hours first."""
def clinics(city: str, st: str, homeless: bool) -> list {
    fields = "SITE_NM,SITE_PHONE_NUM,SITE_URL,SITE_ADDRESS,SITE_CITY,SITE_STATE_ABBR,SITE_ZIP_CD,TOT_OPER_HR_PER_WEEK,HCH_SUB_PROG_IND,GRANTEE_NM";
    base = "SITE_STATE_ABBR='" + st + "' AND HCC_STATUS_DESC='Active'";
    if homeless { base = base + " AND HCH_SUB_PROG_IND='Y'"; }
    rows: list = [];
    if city {
        rows = arcgis(HRSA_HC, base + " AND UPPER(SITE_CITY)='" + city.upper() + "'", fields, "TOT_OPER_HR_PER_WEEK DESC", 3);
    }
    if not rows and not city {
        rows = arcgis(HRSA_HC, base, fields, "TOT_OPER_HR_PER_WEEK DESC", 3);
    }
    return [{
        "name": _clean(r["SITE_NM"]), "phone": fmt_phone(r["SITE_PHONE_NUM"]), "url": _clean(r["SITE_URL"]),
        "address": _clean(r["SITE_ADDRESS"]) + ", " + _clean(r["SITE_CITY"]) + ", " + _clean(r["SITE_STATE_ABBR"]) + " " + _clean(r["SITE_ZIP_CD"])[:5],
        "detail": str(int(r["TOT_OPER_HR_PER_WEEK"] or 0)) + " h/week · sliding-fee care" + (" · homeless program" if str(r["HCH_SUB_PROG_IND"]) == "Y" else "") + " · " + _clean(r["GRANTEE_NM"]),
        "kind": "Community health center", "for": ["Federally Qualified Health Center Sliding-Scale Care", "Medicaid", "CHIP (Children's Health Insurance Program)"],
        "source": "HRSA Health Center Service Delivery Sites (HRSA open data)"
    } for r in rows];
}

walker LocalHelpWalker {
    has category: str = "";
    has city: str = "";
    has state: str = "";
    has homeless: bool = False;
    has summary: dict = {};

    can find with `Root entry {
        t0 = time.perf_counter();
        st = re.sub(r"[^A-Z]", "", str(self.state).upper())[:2];
        city = re.sub(r"[^A-Za-z .'-]", "", str(self.city)).strip().replace("'", "''");
        cat = str(self.category);
        out: dict = {"ok": True, "offices": [], "place": (str(self.city) + ", " if self.city else "") + st, "errors": [], "cached": False};
        if len(st) != 2 or cat not in ["housing", "healthcare", "legal"] {
            out["ok"] = False;
            out["errors"] = ["no state, or no local dataset for this need"];
            self.summary = out;
            report out;
            return;
        }
        key = cat + "|" + city.upper() + "|" + st + "|" + str(self.homeless);
        hit = LOCAL_CACHE.get(key);
        if hit and (time.time() - float(hit[0])) < CACHE_TTL_S {
            out["offices"] = list(hit[1]);
            out["cached"] = True;
        } else {
            jobs: list = [];
            if cat == "housing" {
                jobs = [POOL.submit(phas, city, st), POOL.submit(counselors, city, st)];
            } elif cat == "legal" {
                jobs = [POOL.submit(counselors, city, st)];
            } else {
                jobs = [POOL.submit(clinics, city, st, bool(self.homeless))];
            }
            for j in jobs {
                try {
                    out["offices"] = out["offices"] + j.result(timeout=HTTP_TIMEOUT_S + 0.5);
                } except Exception as ex {
                    out["errors"].append(type(ex).__name__);
                }
            }
            if out["offices"] {
                LOCAL_CACHE[key] = [time.time(), list(out["offices"])];
            }
        }
        out["latency_ms"] = round((time.perf_counter() - t0) * 1000.0, 1);
        self.summary = out;
        report out;
    }
}

sem LocalHelpWalker is "Finds real local offices (HUD housing authorities and counselors, HRSA health centers) for the user's city/state from federal open data; async, cached, time-boxed.";
