## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## Checks run

- [ ] `jac run tests/eval_engine.jac` passes (352 cases + metamorphic check)
- [ ] `jac run tests/check_messages.jac` passes (if a message catalog changed)
- [ ] `jac run tests/check_privacy.jac` passes (if scrubbing or storage changed)

## Engine house rules

Tick what applies and delete the rest. Details in [CONTRIBUTING.md](../CONTRIBUTING.md).

- [ ] A failing case was fixed in `engine/`, not by editing the case
- [ ] Every new trigger word has a benign probe in `tests/golden_probes.json`
- [ ] Crisis handling only adds a hotline, never removes one
- [ ] Person facts come from the parser's flags, not from matching raw text elsewhere
- [ ] No user words reach storage, logs or a model call
- [ ] No real person's message, name or contact details in code, tests or this PR
