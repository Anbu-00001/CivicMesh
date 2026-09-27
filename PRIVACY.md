# Privacy notice

**Last updated: 27 September 2026**

CivicMesh helps people find housing, food, healthcare and legal-aid programs.
Many of the people who use it are in a hard spot. Some are immigrants, some are
leaving an abusive home, and some are thinking about hurting themselves. So this
notice says plainly what happens to what you type.

CivicMesh is an open-source student project. It is **not** a government agency,
a law firm or a benefits office, and using it does not apply you for anything.

## The short version

- **You don't need to tell us who you are.** There's no sign-up. Your browser
  gets a random login (like `visitor_k3j9x2`) the first time you visit. We never
  ask for your name, Social Security number, A-number, address or phone number.
- **If you type an identifier anyway, it's removed before anything is saved or
  sent to a model.** Social Security numbers, A-numbers, phone numbers, emails,
  card numbers, dates of birth, street addresses, long ID numbers and "my name
  is …" become placeholders like `[ssn]`. The app shows you what it removed.
- **Crisis messages stay on our server.** If you write about hurting yourself or
  about abuse, fixed code answers with the right hotline. The message is never
  sent to any AI model.
- **You can delete everything.** Open *Private by design* under the chat box and
  choose **Delete my data**.
- **No ads, no tracking, no selling.** There are no analytics scripts and no
  advertising cookies. We don't share your data with anyone except the two
  providers named below, and only to run the app.

## What is kept, and where

| What | Kept where | For how long |
|---|---|---|
| Your case: the kind of help you need, how urgent it is, your message with identifiers removed, the programs the engine matched, applications you track, and a quality check of each answer | Our server, in a graph database under your random login | Until you press **Delete my data**, or until the server restarts, whichever comes first |
| Your random login (username and a hashed password, nothing about you) | Our server's user list, and your browser's local storage | Until the server restarts. Delete my data clears it from your browser |
| Your picked language | Your browser's local storage | Until you clear it or press Delete my data |
| Anonymous counts: how many chats, which languages, which kinds of help, response times | Our server's memory. Visitor IDs are one-way hashed | Until the server restarts |
| Server logs | Our hosting provider | Only the address of each request and whether it worked, never what you wrote. A test checks this on every change |

The app runs on Hugging Face Spaces' free tier. Its storage is not permanent:
everything above is erased whenever the app restarts. That happens on every
update, and after 48 hours with no visitors.

## What leaves our server

The eligibility engine runs on our server; deciding which programs fit you never
uses an outside service. Two optional features use hosted AI models from
**NVIDIA** (the NVIDIA API Catalog, `build.nvidia.com`):

1. **A short summary in your language** under the answer.
2. **Translation**, only for languages we don't have pre-written translations for.
   In rare cases a message the engine can't place at all is also sent for a
   quick "what does this person need" reading.

These requests carry your message with identifiers removed, or the engine's
answer, which contains program names and numbers rather than your words. Crisis
messages are never sent. NVIDIA's trial terms (sections 2.3–2.4 and 3.3) say it
doesn't keep this content after the session, but it may log it for security and
may use it, without identifying you, to improve its services. If the app's
operator configures a backup model provider, the same scrubbed requests may go
there instead.

**Hugging Face** hosts the app and sees ordinary web traffic, such as your IP
address. Its privacy policy applies to that.

## What we can't promise

- The scrubber catches common patterns. It can miss an identifier written in an
  unusual way, and it can't recognise every name. Please don't type anything you
  don't need to.
- This is a demo on free hosting, without the security review or legal
  agreements (such as a HIPAA business associate agreement) that a real benefits
  office would have. Don't use it for anything you'd need to prove later.
- Answers in 50 languages were translated by machine and haven't been checked by
  native speakers yet. The app says so under each answer and can show you the
  English original.

## Requests from the government or anyone else

We keep as little as possible so there's little to hand over. There are no
names, no contact details, and cases are erased when the server restarts. If we
ever received a legal demand for user data, we would say so here, as far as the
law allows.

## Children

CivicMesh is meant for adults and families looking for help. It doesn't knowingly
collect anything about children beyond what a parent types about their household.

## Questions and changes

Open an issue at https://github.com/Anbu-00001/CivicMesh/issues, and please
**don't include anything about your own situation**, because issues are public.
If this notice changes, the date at the top changes, and the history is in the
repository.

---

*For developers:* the scrubber is `civicmesh/engine/privacy.jac`. It's tested by
`tests/check_privacy.jac`, which covers what must be removed, what must be kept,
and that the facts the engine reads are unchanged. Crisis handling lives in
`walkers/intake.jac` and `walkers/narrate.jac`. Delete my data is
`walkers/forget.jac`. Report-log silencing is `walkers/log_privacy.jac`. CI
checks the server logs for user text on every push.
