"""Privacy guard checks (engine/privacy.jac) — no server, no LLM.

    jac run tests/check_privacy.jac

1. Identifiers are scrubbed: SSN, A-number, phone, email, card, date of birth,
   street address, long ID numbers, "my name is …".
2. Nothing the engine needs is scrubbed: ages, dollar amounts, household
   sizes, ZIP codes, hotline numbers, non-Latin scripts.
3. Scrubbing never changes what the engine reads: parse_intake on the raw
   message and on the scrubbed one agree on category, income, household,
   age, state and crisis flags (the engine reads the raw text anyway; this
   guards the stored/sent copy from losing the facts that matter).
4. Crisis turns are recognised as private in several languages.
"""

import sys;
import from engine.privacy { redact, redaction_kinds, is_private_turn }
import from engine.parse { parse_intake }

glob SCRUB: list = [
    ["My SSN is 123-45-6789", "[ssn]", "123-45-6789"],
    ["my A-number is A123456789", "[a-number]", "123456789"],
    ["A-123-456-789 is on my card", "[a-number]", "456"],
    ["call me at (713) 555-0199", "[phone]", "555-0199"],
    ["my cell 713.555.0199", "[phone]", "555.0199"],
    ["+1 713 555 0199 is my number", "[phone]", "0199"],
    ["email maria.lopez@gmail.com please", "[email]", "maria.lopez"],
    ["card 4111 1111 1111 1111", "[card]", "4111"],
    ["born 03/14/1985", "[date]", "1985"],
    ["I live at 1234 West Main St Apt 5", "[address]", "Main St"],
    ["we're at 55 oak street", "[address]", "oak street"],
    ["vivo en 200 calle Ocho", "[address]", "Ocho"],
    ["vivo en la calle Ocho 200, Miami", "[address]", "Ocho 200"],
    ["my case number is 20250012345", "[number]", "20250012345"],
    ["My name is Maria Lopez and I need food", "[name]", "Maria"],
    ["me llamo Ana García y necesito comida", "[name]", "García"]
];

glob KEEP: list = [
    "I am 67 and need a dr",
    "we have 2 kids no way to pay rent",
    "we earn about $1,200 a month, household of 5",
    "income $2500/month, 3 kids, zip 77002",
    "call 988 now, or 211",
    "SNAP gives $973 a month for 5 people",
    "我住在休斯顿，每月收入1500美元，家里3个人",
    "Tengo 3 hijos y gano $1,800 al mes en Texas",
    "my name is on the lease",
    "vivo en la calle con mis hijos",
    "dormimos en la calle desde hace 2 semanas"
];

glob SAME_FACTS: list = [
    "I'm 72, on $1200/month Social Security, my SSN is 123-45-6789, landlord is evicting me in Houston TX",
    "My name is Maria Lopez, call me at 713-555-0199, we are 4 people earning $2,000 a month and need food",
    "I live at 1234 West Main St, Apt 5, Dallas TX 75201. I'm 34, 3 kids, no income, need housing",
    "My husband hits me, my A-number is A123456789, I need a safe place tonight in Chicago",
    "email me at ana@example.com — I want to kill myself"
];

glob PRIVATE: list = [
    ["I want to kill myself", True],
    ["my husband hits me", True],
    ["我老公打我", True],
    ["quiero quitarme la vida", True],
    ["I need food for my kids", False],
    ["we're not homeless but rent is late", False]
];

with entry {
    fails: list = [];
    n = 0;
    for c in SCRUB {
        n += 1;
        out = redact(c[0]);
        if c[1] not in out or c[2] in out {
            fails.append("scrub: " + repr(c[0]) + " → " + repr(out));
        }
        if c[1] not in redaction_kinds(c[0]) {
            fails.append("kinds: " + repr(c[0]) + " → " + str(redaction_kinds(c[0])));
        }
    }
    for t in KEEP {
        n += 1;
        if redact(t) != t {
            fails.append("over-scrub: " + repr(t) + " → " + repr(redact(t)));
        }
    }
    for t in SAME_FACTS {
        n += 1;
        a = parse_intake(t);
        b = parse_intake(redact(t));
        for k in ["category", "income_annual", "household_size", "age", "state"] {
            if a[k] != b[k] {
                fails.append("facts: " + k + " " + repr(a[k]) + " vs " + repr(b[k]) + " for " + repr(t));
            }
        }
        for f in ["self_harm", "dv"] {
            if (f in a["flags"]) != (f in b["flags"]) {
                fails.append("flag " + f + " changed for " + repr(t));
            }
        }
    }
    for c in PRIVATE {
        n += 1;
        got = is_private_turn(list(parse_intake(c[0])["flags"]));
        if got != c[1] {
            fails.append("private: " + repr(c[0]) + " expected " + str(c[1]));
        }
    }
    print("Privacy guard: " + str(n) + " checks (" + str(len(SCRUB)) + " scrub, " + str(len(KEEP)) + " keep, " + str(len(SAME_FACTS)) + " same-facts, " + str(len(PRIVATE)) + " crisis)");
    for f in fails { print("  ✗ " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
