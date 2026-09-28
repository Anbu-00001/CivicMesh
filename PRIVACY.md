# Privacy notice

**Last updated: 28 September 2026** (Quick exit and private sessions added)

CivicMesh helps people find housing, food, healthcare and legal-aid programs.
Many of the people who use it are in a hard spot. Some are immigrants, some are
leaving an abusive home, and some are thinking about hurting themselves. So this
notice says plainly what happens to what you type. Every statement below is
checked by an automated test, listed at the end.

CivicMesh is an open-source student project. It is **not** a government agency,
a law firm or a benefits office, and using it does not apply you for anything.

## The short version

- **You don't need to tell us who you are.** There's no sign-up. Your browser
  gets a random login (like `visitor_k3j9x2`) the first time you visit. We never
  ask for your name, Social Security number, A-number, address or phone number.
- **Your words are not saved.** Our server reads your message to find programs,
  then keeps only what it understood: the kind of help, how urgent it is, your
  household size and income. It never keeps what you typed.
- **Your words are not sent to any AI model.** The optional short summary and
  the translations are written from the app's own answer (program names, phone
  numbers, the next step), not from your message.
- **Crisis messages get a fixed answer.** If you write about hurting yourself or
  about abuse, fixed code answers with the right hotline.
- **You can delete everything.** Open *Private by design* under the chat box and
  choose **Delete my data**.
- **Quick exit.** The red button at the top, or pressing Shift three times,
  jumps to a weather site right away. The Back button won't bring the chat back.
- **Private session.** If you write about hurting yourself or about abuse, or
  if you switch it on under the chat box, this browser keeps nothing about the
  conversation once you close the tab. In a private session, Quick exit also
  erases your case on the server.
- **No ads, no tracking, no selling.** There are no analytics scripts and no
  advertising cookies.

## What is kept, and where

| What | Kept where | For how long |
|---|---|---|
| What the engine understood from your messages: the kind of help, urgency, household size, yearly income, your language, and your ZIP code if you gave one. Not your words, your immigration status, or your location beyond ZIP | Our server, in a graph database under your random login | Until you press **Delete my data**, or until the server restarts, whichever comes first |
| The programs in your plan (saved as applications you can mark applied, approved or denied; for a crisis they include the hotline) and an automatic quality score for each answer. The score's label is built from the engine's reading, not your words | Same | Same |
| The conversation so far (so a follow-up answer can build on it) | Your browser, sent along with each new message and used in memory only | Until you start a new case or close the page |
| Your random login (username and a hashed password, nothing about you) | Our server's user list, and your browser's local storage (in a private session, only the open tab) | Until the server restarts. Delete my data, Quick exit in a private session, or closing a private tab clears it from your browser |
| Your picked language | Your browser's local storage | Until you clear it or press Delete my data |
| Anonymous counts: how many chats, which languages, which kinds of help, response times | Our server's memory. Visitor IDs are one-way hashed | Until the server restarts |
| Server logs | Our hosting provider | The address of each request and whether it worked, never what you wrote |

The app runs on Hugging Face Spaces' free tier, where storage is not permanent:
everything above is erased whenever the app restarts. That happens on every
update, and after 48 hours with no visitors.

## What leaves our server

Deciding which programs fit you never uses an outside service. Two optional
features use hosted AI models from **NVIDIA** (the NVIDIA API Catalog):

1. **A short summary in your language** under the answer. The model receives the
   kind of need ("food, immediate") and the app's answer: program names, how
   likely each one is, their phone numbers, the first step and the follow-up
   question. It does **not** receive your message, your income, household size,
   location or immigration status. No summary is written for a crisis message.
2. **Translation**, only for languages we don't have pre-written translations
   for. The model receives the app's answer text and button labels, not your
   message.

Your message itself is never sent. The code has an off-by-default switch
(`CIVICMESH_MODEL_READS_MESSAGES=1`) that lets someone running their own copy
send messages the engine can't understand to a model. That's meant only for
models whose terms allow personal data. The public demo doesn't turn it on.
With the switch on, identifiers are removed first and crisis messages are still
never sent. The removal is pattern matching, and its misses are measured (see
below).

**Why we built it this way.** NVIDIA's API Trial Terms of Service forbid sending
"personal data", "protected health information" (§2.6(a)), and "any personal
information relating to an identifiable individual, financial, health or
governmental information" (§4.3). They also say NVIDIA may keep submitted content
for security logging (§2.4) and may use it, without identifying users, "to
improve NVIDIA products and services, including AI models" (§3.3). The only
responsible way to use that service with people in crisis is to not send what
they write.

**Hugging Face** hosts the app and sees ordinary web traffic, such as your IP
address. Its privacy policy applies to that.

## What we can't promise

- The app's answer, which is what gets summarized or translated, says what kind
  of help was found, for example programs for survivors of violence. It carries
  no name, words or contact details, but it isn't nothing.
- The identifier scrubber, used only when the operator switch above is on,
  catches the forms in our tests: Social Security and A-numbers, U.S. and
  international phone numbers, emails, card numbers, dates of birth (numeric and
  spelled out), street addresses, school names, and names introduced as "I'm …",
  "Soy …", "my daughter …" or "my landlord …". It does not catch a bare name
  ("Maria needs food"), a street without a number, or a phone number spelled out
  in words. That's why nothing in the public demo depends on it.
- This is a demo on free hosting, without the security review or legal
  agreements (such as a HIPAA business associate agreement) that a real benefits
  office would have. Don't use it for anything you'd need to prove later.
- Answers in 50 languages, Spanish included, were translated by machine and
  haven't been checked by native speakers yet. The app says so under each
  answer and can show you the English original.

## Requests from the government or anyone else

We keep as little as possible so there's little to hand over. There are no
names, no messages, no immigration status and no contact details, and cases are
erased when the server restarts. If we ever received a legal demand for user
data, we would say so here, as far as the law allows.

## Children

CivicMesh is meant for adults and families looking for help. It doesn't knowingly
collect anything about children beyond the household size a parent gives.

## Questions and changes

Open an issue at https://github.com/Anbu-00001/CivicMesh/issues, and please
**don't include anything about your own situation**, because issues are public.
If this notice changes, the date at the top changes, and the history is in the
repository.

---

*For developers: the tests behind each statement*

| Statement | Test |
|---|---|
| Words not stored; the stored need is the engine's reading | `tests/test_privacy_graph.jac`, E2E P1 and P3 |
| Words not sent to a model; unroutable messages ask instead | E2E P11 (`llm.sync_used` false), `walkers/narrate.jac` has no message parameter |
| Crisis messages: no routing call, no narration | E2E P4–P5, `tests/test_privacy_graph.jac` |
| Quick exit leaves, Back doesn't return, a private exit leaves a fresh identity and erases the case | a headless-browser check run for this release, not yet automated in CI; `frontend.impl.jac` `quickExit` |
| Summary facts carry no income, household, location or status | `facts_for` in `walkers/eligibility.jac` |
| Delete my data removes the case, and only yours | E2E P8–P10, `tests/test_privacy_graph.jac` |
| Server logs hold no user text | CI "Server logs hold no user text" step (`walkers/log_privacy.jac`) |
| Scrubber: what it catches, what it misses | `tests/check_privacy.jac` (gated cases + printed known misses) |
