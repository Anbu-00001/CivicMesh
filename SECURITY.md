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

- No default admin accounts (jac-scale's admin portal is off; the system
  account gets a random password on every boot).
- Walker reports are not echoed to server logs.
- The narrator only accepts facts signed by the server.
- The routing model is off unless an operator opts in.

## Not yet done

This is a student project on free hosting. It has had no independent security
review or penetration test. If you can offer one, please get in touch through
the channel above.
