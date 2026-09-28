"""External check on real people's words: LegalBench "learned_hands" tasks.

    jac run tests/eval_external.jac            # downloads ~7 MB on first run
    jac run tests/eval_external.jac -- misses  # also print dev-half misses

Every other suite in tests/ was written by this project's author, so it only
contains what the author thought of. These are real posts from people
describing their own problems (r/legaladvice), labelled Yes/No per issue by
law students and lawyers in the Learned Hands game (Stanford Legal Design Lab
and Suffolk LIT Lab; packaged by LegalBench, CC BY-NC-SA 4.0). The data is
downloaded at run time into tests/.external/ and never committed.

Protocol against overfitting: each task's rows are split by index parity.
The dev half (odd rows) may be read to find lexicon gaps; the held-out half
(even rows) is only ever scored. Both numbers are printed; the held-out one
is the one to quote. This suite is a measurement, not a gate: long Reddit
narratives are harder than the short requests the router is built for.

What is measured (the engine's own outputs, no model):
  domestic_violence  recall = Yes posts that raise the dv flag (a miss hides a
                     hotline); false alarms = No posts that raise it
  housing / health   recall = Yes posts routed to housing / healthcare (as the
                     top or a secondary category); false-positive rate on No
  immigration        recall = Yes posts where an immigration status was read
                     (citizen, green card, visa, refugee, undocumented, …)
"""

import os;
import sys;
import json;
import urllib.request;
import from engine.parse { parse_intake }

glob BASE: str = "https://huggingface.co/datasets/nguha/legalbench/resolve/main/data/";
glob TASKS: list = ["domestic_violence", "housing", "health", "immigration"];
glob CACHE: str = os.path.join("tests", ".external");

"""Rows (index, text, yes) of one task's test split, cached locally."""
def load_task(task: str) -> list {
    os.makedirs(CACHE, exist_ok=True);
    path = os.path.join(CACHE, "learned_hands_" + task + ".tsv");
    if not os.path.exists(path) {
        url = BASE + "learned_hands_" + task + "/test.tsv";
        with urllib.request.urlopen(url, timeout=120) as r {
            open(path, "wb").write(r.read());
        }
    }
    rows: list = [];
    lines = open(path, encoding="utf-8").read().split("\n");
    for line in lines[1:] {
        parts = line.split("\t");
        if len(parts) >= 3 and parts[0].strip().isdigit() {
            rows.append([int(parts[0]), parts[1], parts[2].strip().lower() == "yes"]);
        }
    }
    return rows;
}

"""Did the engine's reading of `text` hit the task's target?"""
def hit(task: str, p: dict) -> bool {
    cats = [str(p["category"])] + [str(c) for c in list(p.get("secondary", []))];
    if task == "domestic_violence" { return "dv" in list(p["flags"]); }
    if task == "housing" { return "housing" in cats; }
    if task == "health" { return "healthcare" in cats; }
    # Every r/legaladvice post is "legal", so routing is no signal here: count
    # posts where the engine read an immigration status.
    if task == "immigration" { return bool(p.get("citizenship")); }
    return False;
}

with entry {
    show = "misses" in sys.argv;
    summary: dict = {};
    print("External check — LegalBench learned_hands (real r/legaladvice posts, lawyer-labelled)");
    print(f"  {'task':<18} {'half':<9} {'recall (Yes)':>14} {'false pos (No)':>16}");
    for task in TASKS {
        rows = load_task(task);
        for half in ["dev", "held-out"] {
            tp = 0; pos = 0; fp = 0; neg = 0;
            misses: list = [];
            for row in rows {
                if (row[0] % 2 == 1) != (half == "dev") { continue; }
                p = parse_intake(row[1][:4000]);
                h = hit(task, p);
                if row[2] {
                    pos += 1;
                    if h { tp += 1; } elif half == "dev" { misses.append(row[1][:220].replace("\n", " ")); }
                } else {
                    neg += 1;
                    if h { fp += 1; }
                }
            }
            rec = tp / pos if pos else 0.0;
            fpr = fp / neg if neg else 0.0;
            summary[task + "/" + half] = {"recall": round(rec, 3), "false_positive_rate": round(fpr, 3), "yes": pos, "no": neg};
            print(f"  {task:<18} {half:<9} {rec:>8.1%} ({tp}/{pos}) {fpr:>9.1%} ({fp}/{neg})");
            if show and half == "dev" {
                for mm in misses[:25] { print("      miss: " + mm); }
            }
        }
    }
    json.dump(summary, open(os.path.join("tests", "external_report.json"), "w"), indent=2);
}
