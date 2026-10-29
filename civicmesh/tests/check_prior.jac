"""Client-held profile checks (engine/prior.jac) — no server, no LLM.

    jac run tests/check_prior.jac

The case lives in the browser and comes back as `prior` each turn. The server
keeps only fields it could have parsed itself (outside judge, 2026-10-28: a
forged household of 12 and forged flags were scored as given).
"""

import sys;
import from engine.prior { sanitize_prior }

with entry {
    results: list = [];
    real = {"case_text": "I'm homeless with my 2 kids in Ohio, I make 1200 a month", "household_size": 3, "income_annual": 14400,
            "state": "OH", "flags": ["homeless", "children"], "category": "housing", "language": "en", "answered": ["income"]};
    s = sanitize_prior(real);
    results.append(["real facts survive", s["household_size"] == 3 and s["state"] == "OH" and s["income_annual"] == 14400 and "homeless" in s["flags"] and "children" in s["flags"]]);
    forged = dict(real);
    forged["flags"] = ["homeless", "children", "veteran", "dv", "disabled"];
    forged["household_size"] = 12;
    s = sanitize_prior(forged);
    results.append(["forged flags dropped", "veteran" not in s["flags"] and "dv" not in s["flags"] and "disabled" not in s["flags"] and "homeless" in s["flags"]]);
    results.append(["forged household dropped", s["household_size"] != 12]);
    s = sanitize_prior({"case_text": "we need food \n 12", "household_size": 12, "answered": ["household"]});
    results.append(["a typed household answer is kept", s["household_size"] == 12]);
    s = sanitize_prior({"case_text": "need food \n no homeless", "flags": ["homeless"], "answered": ["homeless"]});
    results.append(["a quick-reply flag is kept", "homeless" in s["flags"]]);
    s = sanitize_prior({"case_text": "I'm 72 and need food", "age": 72, "flags": ["senior"]});
    results.append(["an age-derived flag is kept", "senior" in s["flags"]]);
    s = sanitize_prior({"case_text": "food", "age": 999, "income_annual": "lots", "household_size": -4, "state": "ZZ", "zip": "abc12",
                        "citizenship": "king", "language": "<script>", "category": "weapons", "secondary": ["food", 7], "urgency": "now",
                        "answered": ["income", {"x": 1}], "category_conf": 9, "evil": "x"});
    results.append(["ranges and enums enforced", s["age"] == 0 and s["income_annual"] == -1 and s["household_size"] == 0 and s["state"] == "" and s["zip"] == ""
          and s["citizenship"] == "" and s["language"] == "" and s["category"] == "" and s["secondary"] == ["food"] and s["urgency"] == "within_weeks"
          and s["answered"] == ["income"] and s["category_conf"] == 0.5 and "evil" not in s]);
    results.append(["not a dict is empty", sanitize_prior([1, 2]) == {} and sanitize_prior("x") == {} and sanitize_prior(None) == {}]);
    results.append(["case text is capped", len(sanitize_prior({"case_text": "a" * 9000})["case_text"]) == 1500]);
    fails = [r[0] for r in results if not r[1]];
    print("Client-held profile: " + str(len(results)) + " checks");
    for f in fails { print("  ✗ " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
