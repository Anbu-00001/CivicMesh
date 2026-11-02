"""External check on suicide-risk wording no one on this project wrote.

    jac run tests/eval_crisis_external.jac            # downloads ~4 MB on first run
    jac run tests/eval_crisis_external.jac -- misses  # also print dev-half misses

Recall: the Reddit C-SSRS Suicide Dataset (Gaur et al., WWW 2019; Zenodo record
2667859, CC BY 4.0): 500 users' r/SuicideWatch-area histories, each graded by
four practising psychiatrists on the Columbia scale as Supportive, Indicator,
Ideation, Behavior or Attempt. False alarms: every post of the LegalBench
learned_hands tasks (r/legaladvice), people with a problem who mostly aren't at
risk. Both are downloaded at run time into tests/.external/ and never committed.

Protocol against overfitting: rows are split by parity. The dev half (odd) may
be read to find gaps; the held-out half (even) is only ever scored, and that is
the number to quote. This is a measurement, not a gate.

What it can and can't say:
  whole    the user's posts joined and clipped to the chat box's 4,000
           characters. A long history usually says "suicide" somewhere, so this
           flatters the engine.
  first    only the user's first post. Closer to one chat message, but the label
           grades the user, not the post, so a miss isn't always a real miss.
  masked   the whole history with the direct words removed ("suicide", "kill
           myself", "want to die", …): how much the indirect wording carries.
A person typing to this app isn't a Reddit poster, and Supportive users talk
about suicide while helping others, so neither class is a clean negative: they
are reported, not scored as false alarms.
"""

import os;
import re;
import sys;
import csv;
import ast;
import json;
import urllib.request;
import from engine.parse { parse_intake }

glob URL: str = "https://zenodo.org/records/2667859/files/500_Reddit_users_posts_labels.csv?download=1";
glob CACHE: str = os.path.join("tests", ".external");
glob AT_RISK: list = ["Ideation", "Behavior", "Attempt"];
glob OTHERS: list = ["Indicator", "Supportive"];
glob DIRECT: str = "suicid\\w*|kill(?:ing)? (?:my ?self|me)\\b|kms\\b|(?:want|wanna|wanted|wish|ready) (?:to )?(?:die|be dead)|end(?:ing)? (?:my life|it all)|take my (?:own )?life|self[- ]harm\\w*|overdos\\w*";

def load_users -> list {
    os.makedirs(CACHE, exist_ok=True);
    path = os.path.join(CACHE, "reddit_cssrs_500.csv");
    if not os.path.exists(path) {
        with urllib.request.urlopen(URL, timeout=120) as r {
            open(path, "wb").write(r.read());
        }
    }
    csv.field_size_limit(10 ** 8);
    rows: list = [];
    for row in csv.DictReader(open(path, encoding="utf-8", errors="replace")) {
        num = int(re.sub("\\D", "", str(row["User"])) or 0);
        try {
            posts = [str(p) for p in ast.literal_eval(str(row["Post"]))];
        } except Exception {
            posts = [str(row["Post"])];
        }
        rows.append([num, posts, str(row["Label"])]);
    }
    return rows;
}

"""The dataset's authors mapped words to medical concepts when they anonymized
it, and some mappings garbled ordinary English: "feel like" became "feel
hyperactive behavior" and "high school" became "drug abuse school". Undone
here, because people type the original words."""
def flagged(text: str) -> bool {
    text = text.replace("hyperactive behavior", "like").replace("drug abuse", "high").replace("mental depression", "depression");
    f = list(parse_intake(text[:4000])["flags"]);
    return "self_harm" in f or "self_harm_concern" in f;
}

def wilson(k: int, n: int) -> tuple {
    if n == 0 { return (0.0, 0.0); }
    z = 1.96;
    ph = k / n;
    den = 1 + z * z / n;
    mid = (ph + z * z / (2 * n)) / den;
    half = z * ((ph * (1 - ph) / n + z * z / (4 * n * n)) ** 0.5) / den;
    return (max(0.0, mid - half), min(1.0, mid + half));
}

with entry {
    show = "misses" in sys.argv;
    users = load_users();
    summary: dict = {};
    print("External crisis check — Reddit C-SSRS (500 users, psychiatrist-graded)");
    for half in ["dev", "held-out"] {
        part = [u for u in users if (u[0] % 2 == 1) == (half == "dev")];
        risk = [u for u in part if u[2] in AT_RISK];
        hits = {"whole": 0, "first": 0, "masked": 0};
        misses: list = [];
        for u in risk {
            whole = " ".join(u[1]);
            w = flagged(whole);
            hits["whole"] += 1 if w else 0;
            hits["first"] += 1 if flagged(u[1][0]) else 0;
            m = flagged(re.sub(DIRECT, " ", whole, flags=re.I));
            hits["masked"] += 1 if m else 0;
            if not m { misses.append(whole[:300].replace("\n", " ")); }
        }
        summary[half] = {"n": len(risk)};
        for (k, v) in hits.items() {
            (lo, hi) = wilson(v, len(risk));
            summary[half][k] = round(v / max(1, len(risk)), 3);
            print(f"  {half:<9} at-risk {k:<7} {v / max(1, len(risk)):>6.1%} ({v}/{len(risk)})  {lo:.0%}–{hi:.0%}");
        }
        for label in OTHERS {
            rows = [u for u in part if u[2] == label];
            n = len([u for u in rows if flagged(" ".join(u[1]))]);
            print(f"  {half:<9} {label:<15} flagged {n}/{len(rows)} (reported, not scored)");
        }
        if show and half == "dev" {
            for mm in misses[:40] { print("      masked miss: " + mm); }
        }
    }
    print("False alarms — LegalBench learned_hands posts (r/legaladvice)");
    seen: set = set();
    posts: list = [];
    for task in ["domestic_violence", "housing", "health", "immigration"] {
        path = os.path.join(CACHE, "learned_hands_" + task + ".tsv");
        if not os.path.exists(path) {
            with urllib.request.urlopen("https://huggingface.co/datasets/nguha/legalbench/resolve/main/data/learned_hands_" + task + "/test.tsv", timeout=120) as r {
                open(path, "wb").write(r.read());
            }
        }
        for line in open(path, encoding="utf-8").read().split("\n")[1:] {
            parts = line.split("\t");
            if len(parts) >= 3 and parts[0].strip().isdigit() and parts[1] not in seen {
                seen.add(parts[1]);
                posts.append([int(parts[0]), parts[1]]);
            }
        }
    }
    for half in ["dev", "held-out"] {
        part = [p for p in posts if (p[0] % 2 == 1) == (half == "dev")];
        alarms = [p[1] for p in part if flagged(p[1])];
        summary[half]["legal_posts"] = len(part);
        summary[half]["legal_flagged"] = len(alarms);
        print(f"  {half:<9} flagged {len(alarms) / max(1, len(part)):.2%} ({len(alarms)}/{len(part)})");
        if show and half == "dev" {
            for t in alarms[:40] {
                print("      alarm: " + t[:260].replace("\n", " "));
            }
        }
    }
    json.dump(summary, open(os.path.join("tests", "crisis_external_report.json"), "w"), indent=2);
}
