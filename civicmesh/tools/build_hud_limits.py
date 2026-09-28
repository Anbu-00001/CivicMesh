"""Build data/hud_income_limits.json from HUD's official Section 8 income limits.

    pip install openpyxl
    python3 tools/build_hud_limits.py path/to/Section8-FY26.xlsx

HUD publishes limits per metro area / non-metro county (HUD USER, "Income
Limits", FY2026 file Section8-FY26.xlsx). The engine only recognises the
cities in engine/parse.jac's CITIES table, so this keeps the areas for those
cities: each city is mapped to the HUD row for its county (or its town, for
New England), and every mapping is checked against the file — a typo fails the
build instead of silently falling back to the national estimate.
"""

import json
import os
import sys

import openpyxl

# city (as parsed) -> (state, HUD county_town_name). Cities in the same HUD
# metro area share limits, so the county choice for a multi-county city
# doesn't change the number.
CITY_ROWS = {
    "houston": ("TX", "Harris County"), "dallas": ("TX", "Dallas County"), "austin": ("TX", "Travis County"),
    "san antonio": ("TX", "Bexar County"), "el paso": ("TX", "El Paso County"), "fort worth": ("TX", "Tarrant County"),
    "los angeles": ("CA", "Los Angeles County"), "long beach": ("CA", "Los Angeles County"), "san gabriel": ("CA", "Los Angeles County"),
    "san francisco": ("CA", "San Francisco County"), "san diego": ("CA", "San Diego County"), "san jose": ("CA", "Santa Clara County"),
    "oakland": ("CA", "Alameda County"), "fresno": ("CA", "Fresno County"), "sacramento": ("CA", "Sacramento County"),
    "anaheim": ("CA", "Orange County"), "santa ana": ("CA", "Orange County"), "garden grove": ("CA", "Orange County"),
    "stockton": ("CA", "San Joaquin County"), "modesto": ("CA", "Stanislaus County"), "bakersfield": ("CA", "Kern County"),
    "riverside": ("CA", "Riverside County"), "yuba city": ("CA", "Sutter County"),
    "nyc": ("NY", "New York County"), "brooklyn": ("NY", "Kings County"), "bronx": ("NY", "Bronx County"),
    "queens": ("NY", "Queens County"), "flushing": ("NY", "Queens County"), "buffalo": ("NY", "Erie County"),
    "syracuse": ("NY", "Onondaga County"), "utica": ("NY", "Oneida County"),
    "chicago": ("IL", "Cook County"), "miami": ("FL", "Miami-Dade County"), "orlando": ("FL", "Orange County"),
    "tampa": ("FL", "Hillsborough County"), "phoenix": ("AZ", "Maricopa County"), "tucson": ("AZ", "Pima County"),
    "atlanta": ("GA", "Fulton County"), "clarkston": ("GA", "DeKalb County"), "seattle": ("WA", "King County"),
    "boston": ("MA", "Boston city"), "lowell": ("MA", "Lowell city"), "philadelphia": ("PA", "Philadelphia County"),
    "pittsburgh": ("PA", "Allegheny County"), "detroit": ("MI", "Wayne County"), "dearborn": ("MI", "Wayne County"),
    "hamtramck": ("MI", "Wayne County"), "denver": ("CO", "Denver County"), "las vegas": ("NV", "Clark County"),
    "portland": ("OR", "Multnomah County"), "minneapolis": ("MN", "Hennepin County"), "saint paul": ("MN", "Ramsey County"),
    "st. paul": ("MN", "Ramsey County"), "st paul": ("MN", "Ramsey County"), "nashville": ("TN", "Davidson County"),
    "memphis": ("TN", "Shelby County"), "baltimore": ("MD", "Baltimore city"), "silver spring": ("MD", "Montgomery County"),
    "charlotte": ("NC", "Mecklenburg County"), "raleigh": ("NC", "Wake County"), "new orleans": ("LA", "Orleans Parish"),
    "cleveland": ("OH", "Cuyahoga County"), "columbus": ("OH", "Franklin County"), "albuquerque": ("NM", "Bernalillo County"),
    "edison": ("NJ", "Middlesex County"), "jersey city": ("NJ", "Hudson County"), "newark": ("NJ", "Essex County"),
    "paterson": ("NJ", "Passaic County"), "falls church": ("VA", "Falls Church city"), "fairfax": ("VA", "Fairfax County"),
    "st. louis": ("MO", "St. Louis city"), "saint louis": ("MO", "St. Louis city"), "kansas city": ("MO", "Jackson County"),
    "salt lake city": ("UT", "Salt Lake County"), "boise": ("ID", "Ada County"), "omaha": ("NE", "Douglas County"),
    "louisville": ("KY", "Jefferson County"), "indianapolis": ("IN", "Marion County"), "milwaukee": ("WI", "Milwaukee County"),
    "providence": ("RI", "Providence city"), "hartford": ("CT", "Hartford town"), "honolulu": ("HI", "Honolulu County"),
    "anchorage": ("AK", "Anchorage Municipality"), "lewiston": ("ME", "Lewiston city"), "fargo": ("ND", "Cass County"),
    "sioux falls": ("SD", "Minnehaha County"),
    "fort lauderdale": ("FL", "Broward County"),
    "jacksonville": ("FL", "Duval County"),
    "hialeah": ("FL", "Miami-Dade County"),
    "oklahoma city": ("OK", "Oklahoma County"),
    "tulsa": ("OK", "Tulsa County"),
    "virginia beach": ("VA", "Virginia Beach city"),
    "colorado springs": ("CO", "El Paso County"),
    "el cajon": ("CA", "San Diego County"),
    "worcester": ("MA", "Worcester city"),
    "des moines": ("IA", "Polk County"),
    "grand rapids": ("MI", "Kent County"),
    "spokane": ("WA", "Spokane County"),
    "tacoma": ("WA", "Pierce County"),
    "reno": ("NV", "Washoe County"),
    "baton rouge": ("LA", "East Baton Rouge Parish"),
    "birmingham": ("AL", "Jefferson County"),
    "little rock": ("AR", "Pulaski County"),
    "wichita": ("KS", "Sedgwick County"),
    "durham": ("NC", "Durham County"),
    "knoxville": ("TN", "Knox County"),
}


def main(path):
    wb = openpyxl.load_workbook(path, read_only=True)
    ws = wb.worksheets[0]
    rows = ws.iter_rows(values_only=True)
    hdr = next(rows)
    by_place = {}
    for row in rows:
        if row[0] is None:
            break
        d = dict(zip(hdr, row))
        by_place[(d["stusps"], str(d["county_town_name"]))] = d
    areas, cities, missing = {}, {}, []
    for city, key in sorted(CITY_ROWS.items()):
        d = by_place.get(key)
        if not d:
            missing.append(f"{city} -> {key}")
            continue
        code = d["hud_area_code"]
        areas.setdefault(code, {
            "name": d["hud_area_name"], "median": int(d["median2026"]),
            "l50": [int(d[f"l50_{i}"]) for i in range(1, 9)],
            "l80": [int(d[f"l80_{i}"]) for i in range(1, 9)],
            "eli": [int(d[f"ELI_{i}"]) for i in range(1, 9)],
        })
        cities[city] = {"state": key[0], "area": code}
    if missing:
        sys.exit("unmatched HUD rows:\n  " + "\n  ".join(missing))
    out = {
        "_source": "HUD FY2026 Section 8 income limits (HUD USER, Section8-FY26.xlsx; effective May 1, 2026)",
        "_note": "Built by tools/build_hud_limits.py. Only areas for the cities engine/parse.jac recognises.",
        "areas": areas, "cities": cities,
    }
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "hud_income_limits.json")
    with open(dest, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    print(f"{len(cities)} cities -> {len(areas)} HUD areas written to data/hud_income_limits.json")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Section8-FY26.xlsx")
