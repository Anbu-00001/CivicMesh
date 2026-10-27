# Security notes


The Space is public, anonymous and holds a model-provider key, so it's treated as hostile Internet-facing infrastructure, without relying on Hugging Face's platform limits. An audit on 2026-09-29, run against a local copy of the production image (never the live Space), found and closed these:

| Attack path found | What it allowed | Now |
|---|---|---|
| jac-scale's default login-token secret is a public string (`supersecretkey_for_testing_only!`), and jac.toml didn't override it | Forging a login token for any visitor and reading or deleting their case (reproduced: a forged token read a test visitor's domestic-violence case), or claiming the admin role | The secret comes from `CIVICMESH_JWT_SECRET`, generated per boot when unset. The server won't start with a short or default secret. Forged and `alg=none` tokens get 401 |
| `POST /cl/__error__`: anonymous, no size limit | Writing any text into the server logs, which broke the "no user text in logs" promise. One 2 MB body froze the server for over 5 minutes | Answered by the gateway, never forwarded or logged. Bodies over 8 KB are refused in about a millisecond |
| `LocalizeWalker` translated whatever text it was sent | A free translation service on the project's NVIDIA quota, up to 8 parallel model calls per request | Runs only with a token IntakeWalker issued for exactly that text, for that visitor, within 15 minutes, at most 3 times |
| Narration signatures never expired and could be replayed | Spending model calls repeatedly with one signed answer | Tokens are bound to one visitor, expire in 15 minutes and work once |
| Internal walkers, `/function/…`, `/walker/…/{node}`, API-key, jobs, admin and graph routes were reachable | Calling pipeline internals directly, and minting API keys with a forged token | A gateway allowlist: the 11 walkers the client uses, sign-up, login, health, static files and the read-only API docs. Everything else is 404, and jac-scale listens on loopback only |
| No limits on request size, rate or concurrency | Exhausting CPU, memory, storage (unlimited accounts) or the model quota | The gateway and model budget below |

**What runs now** (`cmguard/`, plain Python, unit-tested without Jac):
- **Gateway**, the only public port, in front of jac-scale on 127.0.0.1. It checks the route allowlist, caps body size per route before reading, and caps JSON depth and size. It verifies login tokens before anything reaches jac-scale. Token buckets limit each client address, each visitor and the whole server, more strictly for sign-up and the model-backed walkers. Identical requests from one visitor share one upstream call. Concurrency is capped per address, server-wide and for model-backed walkers, with a short queue and then a 503. Each route has an upstream timeout, and errors are generic.
- **Client address.** Hugging Face's load balancer appends the caller's address to `X-Forwarded-For` (verified with a spoofed header on a public Space). The gateway trusts only that rightmost entry, and only when the direct peer is private, so rotating the header changes nothing.
- **Model budget and circuit breaker** around every litellm call, so fallbacks, retries and parallel translation segments all count. It caps calls per minute, hour and day, estimated tokens per day, concurrent calls and request size, and stops calling after repeated failures. When it refuses, narration and translation are skipped and the deterministic answer is unaffected.
- **Secrets.** Provider errors are redacted before they're returned. CI plants dummy keys and checks that they never appear in responses, pages, scripts or logs.
- **Telemetry.** One aggregate line per interval (rejections by reason, budget refusals, breaker trips), with no addresses, visitor ids or text. The access log is off.

Every threshold is an environment variable with a conservative default: [docs/DEPLOY.md](./DEPLOY.md#abuse-protection-settings). `tests/test_cmguard.py` has 25 unit tests. `tests/security_e2e.py` runs 58 attack simulations against a container wired to a fake model provider: account floods, identity rotation, header spoofing, chat hammering, direct calls to the model walkers, forged, replayed, tampered and cross-visitor tokens, oversized and malformed bodies, concurrent bursts, budget exhaustion, crisis turns and secret exfiltration. Both run in CI on every push.

**Remaining limits:**
- **One process, state in memory.** Rate limits, the replay record and the model budget reset on restart and aren't shared between processes. That's fine for one Space; a multi-process deployment needs a shared store such as Redis.
- **Distributed attacks.** Accounts are free, so the per-address and server-wide limits are what stop an attacker. A large botnet can still use the server-wide allowance: the global buckets and the model budget bound the cost, but the Space can be slow for everyone while it lasts.
- **Cancelled work.** When a caller gives up, its walker thread still runs to the end (Python can't stop a thread); timeouts and concurrency caps bound it.
- **Platform limits.** Hugging Face's own proxy limits aren't relied on and weren't measured.

Other hardening:
- jac-scale bootstraps a login-capable `admin` / `changeme` account and a `__system__` scheduler account by default. The admin portal is disabled in `jac.toml`, and the system password is random on every boot.
- Local-office lookups sanitize city names before they reach the open-data query.
- Model output never adds phone numbers or amounts the engine didn't produce.
- One message costs at most 4,000 characters of parsing: longer text keeps its first and last 2,000 (a crisis sentence can sit at either end of a pasted letter), and the chat box stops at 4,000. An outside review found the money pattern quadratic on digit runs: 100,000 digits took 438 s. It's linear now (0.04 s for a million), and `tests/check_input_limits.jac` holds 19 hostile inputs to a one-second budget.
- Walker reports aren't echoed to stdout (`walkers/log_privacy.jac`); CI scans the container logs for user text.
- Reporting a vulnerability: [SECURITY.md](../SECURITY.md). Privacy guarantees and their limits: [PRIVACY.md](../PRIVACY.md).
