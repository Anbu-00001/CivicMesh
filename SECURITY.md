# Security policy

CivicMesh is used by people in hard situations: immigrants, survivors of abuse,
people in crisis. A security or privacy bug here can hurt someone, so reports
are welcome and taken seriously.

## Reporting a vulnerability

Please **don't open a public issue** for a security or privacy problem.

- Use GitHub's private vulnerability reporting: the repository's **Security**
  tab → **Report a vulnerability**.
- If that isn't available to you, open an issue titled "Security contact
  request" with no details, and a maintainer will reply with a private channel.

Include what you found, how to reproduce it, and what data or users it could
affect. The maintainer aims to acknowledge reports within a week, will say when
a fix ships, and will credit you if you want to be credited.

## Especially in scope

- Anything that lets one visitor read or change another visitor's case.
- User text reaching logs, storage or a model provider, which the
  [privacy notice](./PRIVACY.md) says doesn't happen.
- Ways around the crisis handling: a message that should show 988 or the
  Domestic Violence Hotline but doesn't, or the device-safety features (Quick
  exit, private session) leaving something behind.
- Abuse of the model endpoints, such as using the app as a free relay to its
  model quota.
- Wrong phone numbers or eligibility rules that could misdirect someone. This
  isn't a security bug, but please report it (privately if you prefer).

## What's already hardened

Details and the tests behind them are in the README ("Security notes",
"Privacy") and PRIVACY.md:

- Login tokens are signed with a per-boot secret (`CIVICMESH_JWT_SECRET`), not
  jac-scale's public default; the server refuses to start with a weak one.
- One public port: a gateway (`cmguard/gateway.py`) in front of jac-scale on
  loopback, with a route allowlist, body and JSON caps, token checks, rate
  limits per address, per visitor and server-wide, concurrency caps,
  duplicate collapse and timeouts.
- Narration and translation run only on short-lived, visitor-bound,
  replay-limited tokens over the engine's own answer (`cmguard/tokens.py`).
- A process-wide model budget and circuit breaker around every model call
  (`cmguard/budget.py`); when it refuses, the deterministic answer still works.
- No default admin accounts (jac-scale's admin portal is off; the system
  account gets a random password on every boot).
- Walker reports, client-error reports and request addresses are not written
  to server logs; security telemetry is aggregate counts only.
- The routing model is off unless an operator opts in.
- `tests/security_e2e.py` (59 attack simulations) and `tests/test_cmguard.py`
  run in CI on every push.

## Not yet done

This is a student project on free hosting. It has had no independent security
review or penetration test; the 2026-09-29 audit described in the README was
done by the project itself. Known limits (in-memory, single-process state;
what a large botnet can still do) are listed in the README's "Security notes".
If you can offer an independent review, please get in touch through the
channel above.
