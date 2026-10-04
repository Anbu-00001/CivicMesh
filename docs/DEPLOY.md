# Deploying CivicMesh to Render

Free tier, no credit card. From a clean machine to a live URL in ≈ 15 minutes.

## What you get on Render's free plan

- **0.5 vCPU / 512 MB RAM** Docker web service
- **No credit card required** — sign up with GitHub
- **Sleeps after 15 min of inactivity** — first request after wake takes ~30 s
- **No persistent disk** — the container filesystem survives sleep/wake but is wiped on redeploys
- **Public HTTPS URL** at `https://<service-name>.onrender.com`

What this means for CivicMesh: the SQLite anchor store at `civicmesh/.jac/data/anchor_store.db` keeps the graph between sleep and wake. When you push new code (redeploy), the graph is wiped and `SeedWalker` re-runs on the first request — which is idempotent and rebuilds the demo data. User sessions created on the live URL are lost across redeploys; this is acceptable for a demo.

## Prerequisites

1. **A GitHub account** with this repo pushed to it (public or private).
2. **A free NVIDIA NIM key** from <https://build.nvidia.com> (sign-in with email; no card).
3. **(Optional) Featherless.AI key** from <https://featherless.ai> for transparent LLM fallback when NIM rate-limits.

## One-time setup

1. **Push the repo to GitHub.** The Render blueprint (`render.yaml`), `Dockerfile`, and `.dockerignore` must all be on the branch you're going to deploy from (default: `main`).

2. **Sign up at <https://render.com>** with your GitHub account. No card prompt.

3. **New → Blueprint** in the Render dashboard. Connect your CivicMesh repo. Render reads `render.yaml` and previews the service it's about to create — confirm.

4. **Set the two secret env vars** in the Render dashboard (Service → Environment):
   - `NVIDIA_NIM_API_KEY` = `nvapi-...`
   - `FEATHERLESS_API_KEY` = `fwl-...` *(optional but recommended)*
   These are flagged `sync: false` in `render.yaml`, so Render won't try to read them from the repo.

5. Click **Manual Deploy → Deploy latest commit**.

First deploy takes ~6–8 minutes (Render pulls Python 3.12, installs the byllm/litellm/jaclang stack, then `jac build` compiles the React client). Subsequent deploys are faster.

## Verify

Once Render shows **Live**, open `https://civicmesh.onrender.com/cl/app` (substitute your service name). There is no shared login: each browser gets its own anonymous account on first load. Try:

| Prompt | What you should see |
|---|---|
| *"I need food assistance for my family"* | NavigationWalker plan — SNAP, WIC, food bank with phone numbers |
| *"Who do I call for a domestic-violence safe house?"* | Leads with **1-800-799-7233** |
| *"Necesito ayuda con la renta"* | Spanish input → Spanish reply |
| *"இன்று நான் எங்கே உணவு பெறுவது?"* | Tamil, routed without an LLM → food programs, then a Tamil summary |
| *"I lost my job and need legal help to avoid eviction"* | routes to **legal** + housing, with local housing authorities from HUD open data |

If you get a generic "Page Not Found" right after deploy, the container is mid-boot. Wait 30 s and reload.

## Memory and rate-limit notes

- **512 MB is tight** but fits because model inference is remote (NIM API) and the eligibility engine is pure Python-level math.
- **NVIDIA NIM free tier** rate-limits at ~40 RPM. A chat turn makes **one** LLM call (background narration), plus one time-boxed routing call only when no language lexicon matches — so rate limits no longer block answers; at worst the narration is skipped.
- **Sleep behavior:** if you set a `healthCheckPath`, use `/healthz` (the blueprint uses Render's TCP check). Render pings it every minute. If the page returns 200, the service is considered awake. To prevent sleep during a scheduled demo, hit any page yourself (or use a cron-ping service like [cron-job.org](https://cron-job.org)) in the 15 min leading up to it.

## Abuse protection settings

The container starts `python -m cmguard.serve`: a gateway on the public port in
front of jac-scale on 127.0.0.1 (see the README's "Security notes"). Every
setting below is optional. The defaults suit a free Hugging Face Space (2 vCPU,
one process) and sit well above what real visitors do; per-address limits are
generous because a library or shelter can put many people behind one address.

**Secrets.** Generated per boot when unset; set them only if logins should
survive a restart (they otherwise end with the rest of a free Space's state).

| Variable | Purpose |
|---|---|
| `CIVICMESH_JWT_SECRET` | Signs login tokens. At least 32 characters; jac-scale's public default is refused. jac.toml reads it and the server won't start without it |
| `CIVICMESH_SIGNING_KEY` | Signs the narration and translation tokens |
| `SYSTEM_USER_PASSWORD` | jac-scale's internal scheduler account |

**Client address.** `CIVICMESH_TRUSTED_PROXY_HOPS` (default `1`): how many
`X-Forwarded-For` entries the proxy in front appends. Hugging Face appends one
(verified). Use `0` on a host with no proxy. The header is only read when the
direct peer is a private address.

**Rate limits.** Token buckets written `COUNT/SECONDS` (a burst of COUNT,
refilled over SECONDS). Override any cell with
`CIVICMESH_RL_<CLASS>_<SCOPE>`, e.g. `CIVICMESH_RL_CHAT_IP=150/60`, or `off`.
Body caps: `CIVICMESH_BODY_MAX_<CLASS>` (bytes). Timeouts:
`CIVICMESH_TIMEOUT_<CLASS>` (seconds).

| Class | Routes | Per address | Per visitor | Server-wide | Max body | Timeout |
|---|---|---|---|---|---|---|
| `static` | pages, scripts, images, API docs | 600/60 | — | 12000/60 | — | 30 s |
| `health` | /healthz | 60/60 | — | 600/60 | — | 5 s |
| `register` | POST /user/register | 20/600 | — | 200/600 | 2 KB | 15 s |
| `login` | POST /user/login, /user/refresh-token | 60/600 | — | 900/600 | 2 KB | 15 s |
| `me` | GET /user/me | 180/60 | 40/60 | 3000/60 | — | 10 s |
| `chat` | IntakeWalker | 90/60 | 40/60 | 600/60 | 64 KB | 40 s |
| `model` | NarrateWalker, LocalizeWalker | 60/60 | 12/60 | 180/60 | 32 KB | 60 s |
| `external` | LocalHelpWalker (open-data lookups) | 30/60 | 8/60 | 200/60 | 8 KB | 30 s |
| `light` | Memory, GraphSnapshot, Impact, Platform, ReflectionRead walkers | 240/60 | 60/60 | 4000/60 | 8 KB | 20 s |
| `seed` | SeedWalker | 40/600 | 6/600 | 400/600 | 4 KB | 30 s |
| `forget` | ForgetWalker | 20/600 | 4/600 | 200/600 | 4 KB | 20 s |
| `sink` | POST /cl/__error__ (dropped) | 10/60 | — | 120/60 | 8 KB | — |

**Concurrency and shape.**

| Variable | Default | Meaning |
|---|---|---|
| `CIVICMESH_INFLIGHT_PER_IP` | 6 | API requests in flight per address |
| `CIVICMESH_INFLIGHT_GLOBAL` | 16 | API requests in flight to jac-scale in total |
| `CIVICMESH_INFLIGHT_MODEL` | 6 | Narration/translation requests in flight |
| `CIVICMESH_QUEUE_WAIT_S` | 3 | How long a request waits for a slot before a 503 |
| `CIVICMESH_BODY_READ_S` | 15 | Deadline for receiving a request body |
| `CIVICMESH_JSON_MAX_DEPTH` / `_NODES` / `_STRING` | 12 / 5000 / 20000 | JSON shape caps |
| `CIVICMESH_DEDUP_CHAT_S` / `CIVICMESH_DEDUP_MODEL_S` | 3 / 60 | How long an identical request from the same visitor reuses the first answer |
| `CIVICMESH_TOKEN_TTL_S` | 900 | Lifetime of narration/translation tokens |
| `CIVICMESH_MAX_CONNECTIONS` | 256 | Open connections the gateway accepts |
| `CIVICMESH_LIMITER_MAX_KEYS` | 50000 | Entries per limiter table (idle entries are forgotten after their window) |
| `CIVICMESH_SECURITY_LOG_S` | 60 | Interval of the aggregate security log line |

**Model budget.** Counts every model call the app makes: each model a pool
falls back through, and each parallel translation segment. When it refuses,
narration and translation are skipped and the deterministic answer is
unaffected.

| Variable | Default | Meaning |
|---|---|---|
| `CIVICMESH_LLM_MAX_PER_MIN` | 30 | Model calls per minute (NVIDIA's free tier allows about 40) |
| `CIVICMESH_LLM_MAX_PER_HOUR` | 600 | Model calls per hour |
| `CIVICMESH_LLM_MAX_PER_DAY` | 4000 | Model calls per day |
| `CIVICMESH_LLM_MAX_TOKENS_PER_DAY` | 2000000 | Estimated tokens per day (prompt length / 4 + requested output, corrected by reported usage) |
| `CIVICMESH_LLM_MAX_REQUEST_TOKENS` | 8000 | Largest single request |
| `CIVICMESH_LLM_MAX_CONCURRENT` | 4 | Model calls at once |
| `CIVICMESH_NARRATE_TIMEOUT_S` | 25 | Seconds each model gets for a narration (the answer is already on screen, so this isn't on the critical path). Two models must fit in the gateway's 60 s limit for model calls |
| `CIVICMESH_LLM_WAIT_S` | 2 | Wait for a free slot before refusing |
| `CIVICMESH_LLM_BREAKER_FAILURES` | 5 | Consecutive failures that open the circuit |
| `CIVICMESH_LLM_BREAKER_COOLDOWN_S` / `_MAX_COOLDOWN_S` | 60 / 900 | Open time, doubling on each re-trip up to the maximum |
| `CIVICMESH_LLM_RETIRE_S` | 21600 | How long a model the provider answers 404 or 410 for is skipped (it never counts toward the breaker). When a provider retires a model, change `CIVICMESH_LLM_MODELS` or the defaults in `llm/stubs.jac` |
| `CIVICMESH_LLM_DISABLED` | 0 | `1` turns every model call off (deterministic answers only) |

## Updating

```bash
git push origin main
```

Render auto-deploys on push (because `autoDeploy: true` in `render.yaml`). Watch the build in the Render dashboard → Logs.

## Tearing down

In the Render dashboard: Service → Settings → **Delete Service** at the bottom. Removes the deployment; the GitHub repo is untouched.

## If Render doesn't fit (alternatives)

| Platform | Free? CC? | Sleeps? | Notes |
|---|---|---|---|
| **Render** *(default here)* | yes / no | yes (15 min) | This guide |
| **Koyeb** | yes / typically no, but recently asking for one on some accounts | **no** | Deploy by pointing at the same `Dockerfile`. No card requested → great if you can get past sign-up. |
| **Hugging Face Spaces (Docker SDK)** | yes / no | only on inactivity (slower wake) | Limited to 16 GB ephemeral disk; works for the demo |
| **Fly.io** | trial $5 credit then pay-as-you-go | no | Best UX but now requires a card after the trial |

The `Dockerfile` and `.dockerignore` are portable — any of these platforms can run the same image. Only the platform-specific config file (`render.yaml`, `fly.toml`, etc.) needs to change.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails on `pip install` | RAM during install | Render's free-tier build has more RAM than runtime — should pass. If not, comment unused deps in `requirements.txt`. |
| `jac build app.jac` step hangs > 8 min | bun downloading deps | First build is slow; subsequent builds reuse cached layers. |
| All chats route to EscalationWalker | Graph not seeded yet | The client triggers SeedWalker on login automatically. Log out and back in once, OR `curl -X POST https://<service>.onrender.com/walker/SeedWalker -H "Authorization: Bearer <token>"` |
| LLM returns 429 | NIM rate limit | Set `FEATHERLESS_API_KEY` env var and redeploy |
| Wrong language detected | missing marker words | add the case to `civicmesh/tests/golden_i18n.json`, then the words to `civicmesh/engine/i18n.jac`; run `jac run tests/eval_engine.jac` |
| Long pause on first request | Service was asleep | Expected; wait ~30 s |
