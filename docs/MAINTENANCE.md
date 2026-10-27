# Maintenance plan: living with Jac, and leaving it if we have to

CivicMesh is written in [Jac](https://www.jac-lang.org/) (jaclang 0.15.1), a
young language with a small community. A reviewer called that out, fairly:
if nobody else can read, audit or maintain the code, good code is still a dead
end. This page explains why the project is not locked in, what's pinned, and how
a maintainer would move it off Jac, one layer at a time and with tests that
prove nothing changed.

## What is actually Jac-specific

| Layer | Lines | What it is | Jac-specific? |
|---|---:|---|---|
| `engine/` | 5,001 | Parsing, scoring, the policy tables, planning, routes, message catalogs, privacy scrubbing. Pure functions over dicts; the only imports are the standard library | **No.** `jac jac2py` turns it into plain Python that runs without Jac installed. CI does this on every push and runs all 352 cases on the result |
| `data/` | JSON | 40 programs, transitions, 51 message catalogs | No |
| `tests/golden*.json` | JSON | 439 cases and 14 multi-turn conversations: the behaviour spec | No. A rewrite in any language can be checked against them |
| `walkers/` + `graph/` | 2,577 | Graph I/O: store the case, run the pipeline, snapshot, delete | Yes. This is Jac's object-spatial model (nodes, edges, walkers) on jac-scale's SQLite store. `jac eject` outputs Python, but it still imports the jaclang runtime |
| `llm/` | 404 | Two model calls via byllm (routing fallback, narration) plus translation | Partly. byllm sits on litellm; the calls are small and replaceable with plain litellm |
| `components/`, `frontend.*` | 4,930 | The web client (jac-client, compiled to React) | Yes, but `jac eject` outputs a standard React + Vite project |

So the decisions that matter, like who is eligible, which question comes next
and what the crisis line says, live in the part that is already portable. The
Jac-specific part is plumbing.

## Escape hatches, verified

1. **Engine → Python, on every push.** `tools/eject_engine.sh` transpiles
   `engine/*.jac` and the eval harness with `jac jac2py`, fails if the output
   mentions `jaclang`, and runs the eval with a Python that has no Jac
   packages: 1009/1009 checks, the same as the Jac run. The `portable` CI job
   runs it on every push. One trap: `jac2py` prints through a terminal
   console that hard-wraps long lines at the terminal width, which turns long
   regex literals into a `SyntaxError`. The script sets `COLUMNS=100000`; do
   the same if you run `jac2py` by hand. The Python is uploaded as the `civicmesh-engine-python` artifact,
   so a copy of the logic in a mainstream language is always one click away.
2. **Whole project → Python + JavaScript.** `jac eject . -o ../civicmesh-ejected`
   writes a `backend/` (Python) and a `frontend/` (React + Vite). Tried on
   27 September 2026: it works. 34 of the 51 backend files still import the
   jaclang runtime, all in the walker and graph layer.
3. **Rewrite the graph layer if needed.** The walker layer is about 2,600 lines
   of "load the person's nodes, call the engine, write the verdicts". The graph is
   small: one person, their needs, and 40 programs with rules and forms. It maps
   onto SQLite tables or NetworkX without loss. The HTTP contract to keep is the
   walker endpoints the client calls. `tests/e2e_http.py` pins that contract with
   69 checks and runs in CI against the production Docker image.

## Keeping the current stack healthy

- **Everything is pinned.** `requirements.txt` pins every package, including
  `jaclang==0.15.1`, `jac-scale==0.2.17`, `jac-client==0.3.15`, `byllm==0.6.7`
  and `litellm==1.82.6`. The Docker image is reproducible from it.
- **Upgrades come as pull requests, tested.** Dependabot opens one weekly pull
  request for GitHub Actions and security-only pull requests for Python
  packages, and CI runs the full suite on each. Python version bumps are off:
  jaclang and byllm pin litellm and its dependencies exactly, so a grouped bump
  of the other 50 packages couldn't even install. `main` is protected: nothing
  lands without a pull request that passes the engine, portable and end-to-end
  jobs.
- **The Jac stack is held at those pins on purpose.** The first grouped Jac
  upgrade (jaclang 0.16.7, jac-scale 0.2.31, jac-client 0.3.25, byllm 0.6.19)
  passed the engine and portable jobs but failed end-to-end: the new jac-scale
  starts in microservice mode, its gateway listens on port 8000 instead of 7860,
  and the walker services never report healthy, so the app doesn't serve.
  Dependabot ignores the Jac packages until that migration is done on a branch.
  CI's end-to-end job shows when it works; then delete the `ignore` block in
  `.github/dependabot.yml`.
- **Known Jac quirks are written down where they're worked around:**

  | Quirk (jaclang 0.15.1) | Workaround | Where |
  |---|---|---|
  | The typed-query topology index goes stale after a walker's first write | `topology_index = false` | `jac.toml` |
  | `report` also prints every report to stdout, so user text reached the server logs | swap in a non-printing `log_report` after walkers load | `walkers/log_privacy.jac` |
  | litellm's NIM provider drops `max_retries`, so SDK retries stack into 40 s waits | pin the OpenAI SDK to zero retries | `llm/stubs.jac` |
  | Walker entry points match the type `` `Root ``, not the instance `root` | — | noted in `walkers/forget.jac` |
  | In the CLI's local store (`jac run` / `jac test`), removing an edge or node leaves a dangling reference: the third process to open the store fails with "EdgeAnchor … is not a valid reference". Reproduced with a 30-line script and no app code. The jac-scale server persists deletions correctly: verified by deleting a visitor, restarting the container three times, and reusing both that visitor and another one | tests start from a clean store (`rm -rf .jac/data` in CI; locally `docker run --tmpfs /w/.jac/data …`) | `.github/workflows/ci.yml` |

- **Tests that don't need Jac knowledge to read.** The goldens are JSON, and the
  end-to-end script is stdlib Python. The translation review sheet
  (`tools/review_sheet.py`) is stdlib Python too.

## Keeping the program data correct

Benefit rules change every fiscal year, and phone numbers and links drift.
Two jobs keep the catalog honest, and CI enforces the first:

- **Contacts, at least yearly.** From `civicmesh/`, run
  `python3 tools/check_contacts.py`. It fetches each program's page, records
  the HTTP status and whether the listed phone number is on it, and dates the
  record in `data/verification.json`. "Unconfirmed" means a person has to
  look: about half of the government pages refuse scripted requests. When you
  check one by hand, record what you saw under `contact_manual`
  (`checked`, `how`, `source`). `tests/check_verification.py` fails CI when a
  program has no record or its newest check is over a year old. The first run
  (2026-10-27) found three numbers that belonged to someone else and two dead
  links, so don't skip the hand checks.
- **Rules, every October and after any new law.** USDA publishes SNAP's
  October COLA around August; HHS publishes poverty guidelines in January;
  HUD publishes income limits around April. Update `engine/policy.jac`, then
  run both oracles against PolicyEngine US (`tools/oracle_policyengine.py`
  for SNAP, `tools/oracle_programs.py` for Medicaid, CHIP, school meals and
  WIC; setup is in each file's docstring) and record the result under `rules`
  in `data/verification.json`. A disagreement is a lead: check the published
  source before changing either side.

## For a new maintainer

Jac reads like Python with braces. Start with `engine/`: it's plain functions,
and `COLUMNS=100000 jac jac2py engine/score.jac` shows the Python equivalent of any file. Then
read `walkers/intake.jac`, the per-turn pipeline. Run `jac run tests/eval_engine.jac`
before and after every change. CI runs it too, along with the catalog, privacy,
walker and HTTP checks.
