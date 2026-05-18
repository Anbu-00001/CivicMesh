# CivicMesh — Devpost Submission

## Inspiration

Tens of millions of vulnerable people — single mothers, undocumented families, elderly tenants on fixed incomes — don't know which programs they qualify for, what documents they need, or which agency to call first. The American safety net is real (Section 8 vouchers, SNAP, WIC, LIHEAP, Medicaid, legal aid), but it lives behind bureaucratic walls: fragmented websites, English-only intake forms, and screening logic that takes a trained caseworker to decode.

We watched relatives navigate these systems. A 2-day SNAP application can take a week, and an eligibility denial often hides the real reason. We wanted a single front door that speaks any language, knows every program, and produces a ranked action plan in under a minute.

## What it does

CivicMesh accepts a free-form message in any language — "Soy madre soltera con 2 niños y necesito ayuda con vivienda" — and routes it through a five-walker agent pipeline running on the Jac runtime:

- **IntakeWalker** detects language, finds or creates a `PersonNode` reachable from `root`, and extracts a structured `NeedProfile` (category + urgency + free-form details) from the conversation.
- **EligibilityWalker** scores all 40 seeded `ResourceNode`s against the profile using `check_eligibility()`, traversing `governed_by` edges to read each rule and writing match scores back as edge attributes.
- **NavigationWalker** sequences eligible resources into an ordered `ActionPlan`, persists one `ApplicationNode` per recommended step on the `applied_to` edge, and returns the plan with summary + next action.
- **MemoryWalker** snapshots session state for return visits — refresh the browser and the same user reloads the same graph because Jac auto-persists everything reachable from `root`.
- **EscalationWalker** is a byllm ReAct loop with three tools (`check_emergency_resources`, `find_appeal_orgs`, `assess_safety_risk`) that fires when zero resources match. It composes a personalized crisis message in the user's language.

Two utility walkers complete the system: **TranslateWalker** batch-translates the bot reply + suggestion chips into the detected language (with a session-level translation cache to stay inside free-tier LLM budgets), and **ImpactWalker** traverses every `PersonNode` and `ApplicationNode` to aggregate live dashboard stats — no mocks.

Every chat response shows the full reasoning trace: numbered step list with the walker that ran, the input it saw, the structured output it produced, and a one-paragraph reasoning prose explaining the choice.

## How we built it

- **Jac language** (jaclang 0.15.1) for the entire stack — both the agent pipeline and the React-rendered frontend, compiled to JS via `jac-client`.
- **byllm** for LLM-as-function. Every stub in `llm/stubs.jac` is a typed Jac `def` decorated with `by llm()`. byllm reads the `sem` strings on each parameter and return type to auto-document the prompt; we never hand-wrote a prompt template. The escalation walker uses byllm's ReAct loop with `tools=[...]` for multi-step crisis routing.
- **jac-scale** for transparent REST/WebSocket auto-generation. Every walker becomes an endpoint at `/walker/{Name}` and the OpenAPI doc lives at `/docs`. EscalationWalker is exposed as a WebSocket walker for streaming.
- **NVIDIA NIM** (meta/llama-3.1-8b-instruct) as the primary LLM provider via litellm. Featherless.AI is configured as a fallback for resilience.
- **Graph-native persistence**. All `PersonNode`, `NeedNode`, `ResourceNode`, `ApplicationNode`, and edge instances are reachable from the per-user `root`. Jac auto-persists the graph; we wrote zero save/load code.

The frontend is a 5-tab single-page app: **Chat** (with inline streaming reasoning trace + suggestion chips), **Graph** (live SVG visualization of which walker visited which node, with hover tooltips, "Why this path?" edge-label overlay, and animated traveling beams along visited edges), **Action Plan** (impact-score widget calculating estimated $/year in benefits unlocked, with SVG status icons), **Telemetry** (per-walker call cards showing input/output type and tool usage), and **Impact** (aggregate dashboard pulled live from ImpactWalker).

A landing page with animated mesh gradient, glass cards, and a tilted walker-deck visualization sells the product in under 10 seconds. A Cmd+K command palette gives keyboard-first navigation between tabs.

## Challenges we ran into

**JS Object iteration in Jac→JS compilation.** Jac `for k in some_dict` compiles to `for (x of obj)` which requires `Symbol.iterator`. Plain JSON-deserialized JS objects don't have it, so iterating an LLM-returned dict on the client threw `TypeError: languages is not iterable`. Fix: have walkers emit lists of `{key, count}` pairs rather than raw dicts, so the client gets an iterable array and the schema stays explicit.

**`dict(plainObj)` compiles to `Object.fromEntries(plainObj)`** which crashes on plain objects (expects an iterable of pairs). Burned us twice in `GraphViz.renderLastEvent`. Solution: access properties directly without the cast.

**Walker chain `reports` ordering**. byllm walker chains emit reports inner-first, so the outermost walker's payload is `reports[len-1]`, not `reports[0]`. Several walkers were reading the wrong slot before we noticed.

**React closure staleness across rapid setState bursts.** Multiple `setState` calls inside one synchronous handler all use the stale closure, so the second update overwrites the first. Fixed by accumulating into a local variable and dispatching once at the end.

**JSX `/* ... */` comments render as text** in Jac JSX — they aren't stripped. The landing page initially showed `/* HERO */` as a literal user-visible string until we removed them.

**Multilingual LLM reliability**. byllm's `translate_batch` would silently skip items occasionally. We added a per-item equality check after the batch (if the output equals the input but the target language isn't English, flag for retry) and a single retry batch, plus a session-level `translation_cache` so repeat strings + languages cost zero LLM calls.

## Accomplishments we're proud of

- **Multilingual end-to-end** — Tamil, Hindi, Spanish, Arabic, English all round-trip through the pipeline with the bot reply, suggestion chips, and reasoning trace all rendered in the user's detected language.
- **Transparent agent reasoning** — every response carries a step-by-step trace panel showing what each walker did, what it saw, what it output, and why. No "trust me" black box.
- **Real seeded resources** — 40 actual federal/state programs (Section 8, SNAP, WIC, LIHEAP, Medicaid, Catholic Charities, 211, etc.) with real phone numbers. Judges can google any name and find it.
- **Graph-native, not graph-decorative** — every node we create is reachable from `root` and persists across browser refresh. Demo loop: chat → refresh → session loads.
- **Live graph visualization** — the Graph tab shows the real walker traversal frame-by-frame using events emitted by the chat pipeline, not a hardcoded animation.
- **byllm-idiomatic LLM stubs** — every prompt is generated from `sem` strings on the return type's fields, so there are zero hand-crafted prompt templates anywhere in the codebase.

## What we learned

Jac's object-spatial paradigm is genuinely different from Python with classes. `walker` + `visit` + `here` + typed edges create a control flow that reads as "where am I in the graph?" rather than "what function should I call next?" Once we leaned into idiomatic walker abilities split by node type (`can score with PersonNode entry`), the code shortened by 30–40% and the graph traversal became visually obvious.

byllm's `sem` strings change how you think about prompts. You stop writing prompts and start writing semantic documentation. The LLM gets a richer signal because it reads the field's *meaning*, not its name. Multilingual reliability improved measurably once we tightened the `sem` strings on `NeedProfile.urgency` and `EligibilityResult.match_score`.

jac-scale auto-registering every walker as a REST endpoint plus a WebSocket variant collapsed what would have been a FastAPI + Uvicorn + manual routing project into a 30-line `app.sv.jac`.

## What's next

- **Real partner integrations** — wire actual SNAP and Section 8 application APIs (some states expose them) so the action plan can pre-fill forms.
- **Caseworker hand-off mode** — a second view where a trained navigator picks up a session, reviews the agent's reasoning trace, and approves before submission.
- **Mobile-first PWA** — the populations we serve are smartphone-only; the current responsive layout needs a focused phone build.
- **GIS proximity** — `ResourceNode` already has an address field; add zip-distance ranking to the eligibility score.
- **Outcome telemetry** — link `ApplicationNode.status` to a real follow-up flow so the Impact tab's approval rate becomes ground-truth, not just optimistic.

## Built with

Jac · Jaseci · byllm · jac-scale · jac-client · NVIDIA NIM (llama-3.1-8b-instruct) · Featherless.AI (fallback) · litellm · React 18 · Vite · SMIL SVG animations · MongoDB (via jac-scale auto-persistence)

---

Built for JacHacks Spring 2026.
