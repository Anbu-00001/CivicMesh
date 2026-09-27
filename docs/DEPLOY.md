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
- **Sleep behavior:** Render pings your `healthCheckPath` (set to `/docs`) every minute. If the page returns 200, the service is considered awake. To prevent sleep during a scheduled demo, hit any page yourself (or use a cron-ping service like [cron-job.org](https://cron-job.org)) in the 15 min leading up to it.

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
