"""Input-cost checks — no server, no LLM.

    jac run tests/check_input_limits.jac

An outside review found the money pattern quadratic on long digit runs
(10,000 digits took seconds) and no limit on message length. These checks
keep both closed:

1. MONEY_RE stays linear: 100,000 digits in under a second.
2. parse_intake reads at most 4,000 characters (first and last 2,000), so a
   1 MB message costs about what a 4,000-character one does.
3. Hostile 4,000-character inputs (digit runs, repeated trigger words,
   negations, one repeated letter, scripts) each parse within a budget.
4. Clipping keeps both ends: a crisis sentence at the end of a long letter
   still raises its flag.
"""

import re;
import sys;
import time;
import from engine.parse { parse_intake, clip_message, MONEY_RE, MAX_MESSAGE_CHARS }

glob BUDGET_S: float = 1.0;

with entry {
    fails: list = [];
    worst = 0.0;
    worst_name = "";

    t0 = time.perf_counter();
    list(re.finditer(MONEY_RE, "1" * 100000));
    dt = time.perf_counter() - t0;
    if dt > BUDGET_S { fails.append(f"MONEY_RE on 100,000 digits took {dt:.2f} s"); }

    hostile: dict = {
        "digits": "1" * 4000, "digit commas": "1," * 2000, "dollar signs": "$" * 4000, "dollar amounts": "$1 " * 1333,
        "spaces": " " * 4000, "one letter": "a" * 4000, "relation words": "my husband " * 363,
        "negations": "i don't have a " * 266, "no no": "no " * 1333, "social security": "social security " * 250,
        "violence verbs": "he hit " * 571, "accents": "é" * 4000, "cjk": "我" * 4000, "arabic": "ب" * 4000,
        "apostrophes": "'" * 4000, "glottal": "tz'" * 1333, "alnum": "abc123" * 666, "dots": "..." * 1333,
        "no punctuation": "we need help with rent and food because " * 100
    };
    for (name, text) in hostile.items() {
        t0 = time.perf_counter();
        parse_intake(text);
        dt = time.perf_counter() - t0;
        if dt > worst { worst = dt; worst_name = name; }
        if dt > BUDGET_S { fails.append(f"parse_intake on 4,000 chars of {name} took {dt:.2f} s"); }
    }

    big = "we are behind on rent " * 50000;
    t0 = time.perf_counter();
    parse_intake(big);
    dt = time.perf_counter() - t0;
    if dt > BUDGET_S { fails.append(f"a {len(big):,}-character message took {dt:.2f} s"); }
    if len(clip_message(big)) > MAX_MESSAGE_CHARS + 3 { fails.append("clip_message kept more than 4,000 characters"); }

    letter = "Dear tenant, this notice concerns the lease. " * 200 + "I can't take it anymore, I want to die.";
    if "self_harm" not in parse_intake(letter)["flags"] { fails.append("a crisis sentence at the end of a long letter was clipped away"); }
    opening = "My husband hits me. " + "The notice says the lease ends. " * 200;
    if "dv" not in parse_intake(opening)["flags"] { fails.append("a violence sentence at the start of a long letter was clipped away"); }

    print("Input-cost checks: MONEY_RE linear, 4,000-character clip, " + str(len(hostile)) + " hostile inputs");
    print(f"  slowest hostile input: {worst_name} ({worst * 1000:.0f} ms, budget {BUDGET_S * 1000:.0f} ms)");
    for f in fails { print("  FAIL " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
