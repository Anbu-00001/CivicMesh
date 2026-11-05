"""Where a ZIP code or a county is, for messages that name no state ("I live in
43215", "Cook County"): a blind audit (2026-11-02) found both gave no state, so
the state's own programs never showed.

The first three digits of a ZIP belong to one state, apart from the exceptions
written out below. 340 (military mail) and 008 (Virgin Islands) have no entry.
Counties are the largest ones whose name means one place to most people, and a
state named in the same message always wins.
"""
import re;

glob ZIP_PREFIXES: dict = {
    "AL": [[350, 369]], "AK": [[995, 999]], "AZ": [[850, 865]], "AR": [[716, 729]], "CA": [[900, 961]],
    "CO": [[800, 816]], "CT": [[60, 69]], "DE": [[197, 199]], "DC": [[200, 200], [202, 205]],
    "FL": [[320, 339], [341, 349]], "GA": [[300, 319], [398, 399]], "HI": [[967, 968]], "ID": [[832, 838]],
    "IL": [[600, 629]], "IN": [[460, 479]], "IA": [[500, 528]], "KS": [[660, 679]], "KY": [[400, 427]],
    "LA": [[700, 714]], "ME": [[39, 49]], "MD": [[206, 219]], "MA": [[10, 27], [55, 55]], "MI": [[480, 499]],
    "MN": [[550, 567]], "MS": [[386, 397]], "MO": [[630, 658]], "MT": [[590, 599]], "NE": [[680, 693]],
    "NV": [[889, 898]], "NH": [[30, 38]], "NJ": [[70, 89]], "NM": [[870, 884]], "NY": [[5, 5], [100, 149]],
    "NC": [[270, 289]], "ND": [[580, 588]], "OH": [[430, 459]], "OK": [[730, 732], [734, 749]],
    "OR": [[970, 979]], "PA": [[150, 196]], "PR": [[6, 7], [9, 9]], "RI": [[28, 29]], "SC": [[290, 299]],
    "SD": [[570, 577]], "TN": [[370, 385]], "TX": [[733, 733], [750, 799], [885, 885]], "UT": [[840, 847]],
    "VT": [[50, 54], [56, 59]], "VA": [[201, 201], [220, 246]], "WA": [[980, 994]], "WV": [[247, 268]],
    "WI": [[530, 549]], "WY": [[820, 831]]
};

glob COUNTY_STATES: dict = {
    "cook": "IL", "harris": "TX", "maricopa": "AZ", "miami-dade": "FL", "miami dade": "FL", "tarrant": "TX",
    "bexar": "TX", "broward": "FL", "santa clara": "CA", "alameda": "CA", "palm beach": "FL", "hennepin": "MN",
    "allegheny": "PA", "cuyahoga": "OH", "mecklenburg": "NC", "salt lake": "UT", "multnomah": "OR",
    "milwaukee": "WI", "travis": "TX", "hillsborough": "FL", "king": "WA", "clark": "NV"
};

glob COUNTY_RE: str = "\\b(" + "|".join(COUNTY_STATES.keys()) + ") county\\b|\\bcondado de (" + "|".join(COUNTY_STATES.keys()) + ")\\b";

# What makes five digits an address: the words before them, or nothing at all
# before them. "I owe 12000" has neither.
glob ZIP_CUE_LEFT: str = "(?:^\\W*|\\b(?:in|near|around|zip|zip ?code|zipcode|postal code|c[oó]digo postal|area|from|at)(?: is| es|:)?\\W*|\\b[a-z]{2,},?\\s+[a-z]{2}\\s+|,\\s*)$";
glob ZIP_NOT_RIGHT: str = "^\\s*(?:in |of |worth of )?(?:debt|back rent|rent|owed|income|savings|medical|bills?|people|cases?|miles|dollars)\\b";

"""The state a ZIP code belongs to, or "" if it has none."""
def state_of_zip(zip_code: str) -> str {
    z = str(zip_code);
    if len(z) != 5 or not z.isdigit() { return ""; }
    p = int(z[:3]);
    for (st, spans) in ZIP_PREFIXES.items() {
        for span in spans {
            if span[0] <= p <= span[1] { return st; }
        }
    }
    return "";
}

"""The state a ZIP in this message points to: only where the words around it read as an address."""
def state_from_zip(low: str, start: int, end: int, zip_code: str) -> str {
    if not re.search(ZIP_CUE_LEFT, low[max(0, start - 30):start]) { return ""; }
    if re.match(ZIP_NOT_RIGHT, low[end:end + 24]) { return ""; }
    return state_of_zip(zip_code);
}

"""The state of a county named in the message, as (state, start, end), or ("", 0, 0)."""
def state_from_county(low: str) -> tuple {
    m = re.search(COUNTY_RE, low);
    if not m { return ("", 0, 0); }
    return (COUNTY_STATES[m.group(1) or m.group(2)], m.start(), m.end());
}
