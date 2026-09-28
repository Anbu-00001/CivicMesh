# Contributing

Thank you. The most useful contributions, in order:

1. **Native-speaker review of a language.** See
   [docs/TRANSLATION_REVIEW.md](./docs/TRANSLATION_REVIEW.md). 0 of 50 catalogs are
   reviewed yet, and the safety-critical rows of one language are a small, concrete
   start.
2. **Real wording we get wrong.** If CivicMesh misreads how someone actually
   describes their situation, open an issue with a *de-identified* version of
   the sentence and what it should have understood. Never paste anyone's real
   message, name or contact details.
3. **Corrections to program data or rules.** Wrong phone numbers, closed
   programs, outdated income limits, immigrant-eligibility rules. Cite a source.
4. Code. Please open an issue first for anything bigger than a fix.

## Running the checks

```bash
cd civicmesh
jac run tests/eval_engine.jac        # 350 cases + metamorphic check; must PASS
jac run tests/check_messages.jac     # every catalog: keys, placeholders, numbers
jac run tests/check_privacy.jac      # scrubber: caught, kept, documented misses
rm -rf .jac/data && jac test tests/test_privacy_graph.jac   # in-process walkers
jac run tests/eval_external.jac      # real posts (measured, not gated)
```

With the app running (`docker build -t civicmesh . && docker run -p 7860:7860 civicmesh`):
`python3 civicmesh/tests/e2e_http.py http://localhost:7860`.

CI runs all of these on every pull request.

## House rules for the engine

- **Fix the lexicon, never the test case.** When a case fails, the fix goes in
  `engine/`, and the case stays as written.
- **Every trigger word needs a benign case.** When you add a word to a flag
  lexicon, add a probe to `tests/golden_probes.json` where that word appears in
  another sense (see "the Salvation Army", "a car parked on the street").
- **Crisis detection is escalate-only.** It may add a hotline, never suppress
  one. False alarms are acceptable; misses are not.
- **Person facts have one source of truth**: the parser's flags. Don't match
  raw text for them elsewhere.
- **No user words in storage or model calls.** See `engine/privacy.jac` and PRIVACY.md.

## Code of conduct

Be kind. Many of the people this app serves are having the worst week of their
lives; keep that in mind in issues and reviews too.
