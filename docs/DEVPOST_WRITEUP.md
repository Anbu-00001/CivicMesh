# CivicMesh — Devpost Submission

## Inspiration

Tens of millions of vulnerable people — single mothers, undocumented families, elderly tenants on fixed incomes — don't know which programs they qualify for, what documents they need, or which agency to call first. The American safety net is real (Section 8 vouchers, SNAP, WIC, LIHEAP, Medicaid, legal aid), but it lives behind bureaucratic walls: fragmented websites, English-only intake forms, and screening logic that takes a trained caseworker to decode.

We watched relatives navigate these systems. A 2-day SNAP application can take a week, and an eligibility denial often hides the real reason. We wanted a single front door that speaks any language, knows every program, and produces a ranked action plan in under a minute.

## What it does

CivicMesh accepts a free-form message in any language — "Soy madre soltera con 2 niños y necesito ayuda con vivienda" — and routes it through a **seven-walker agent pipeline** running on the Jac runtime. Two of those walkers are genuinely novel for civic-tech AI and form the core of our submission:

### Three innovations no civic-tech AI project has shipped before

**1. Escape Path Pathfinder — multi-hop graph reasoning over civic-resource progressions.** When direct eligibility scoring fails, instead of routing the user to a generic crisis message, we run bounded breadth-first search over a new `leads_to` typed edge representing real-world civic-aid transitions (Emergency Shelter → Rapid Re-Housing → Section 8 priority list; SNAP → WIC automatic cross-enrollment; FQHC → Medicaid via patient navigator). The PathfinderWalker walks up to 3 hops and surfaces 1–3 escape paths ranked by total time-to-resolution. This is multi-hop reasoning over a civic knowledge graph — the 2026 agentic-RAG frontier ([+23.1 pts vs flat retrieval per Mem0's benchmark](https://mem0.ai/blog/state-of-ai-agent-memory-2026)) — applied to social services. The civic safety net is intrinsically a multi-step graph maze; this is the right algorithm to navigate it.

**2. Outcome-Learning Eligibility — the graph that gets smarter from real applications.** Every `EligibilityRuleNode` carries `prior_success_rate`, `prior_attempts`, and `prior_approvals` fields. When `ApplicationNode.status` transitions to approved or denied, MemoryWalker walks back to the gating EligibilityRuleNode and updates a Laplace-smoothed success prior. EligibilityWalker on subsequent turns blends the LLM's raw `match_score` with this learned prior — `final = (1-blend) × LLM_score + blend × prior × 100` where `blend = attempts / (attempts + 20)`. Cold-start: trust LLM entirely. After 20+ outcomes: prior contributes ~50%. Rules that fail in practice get demoted; rules that work get amplified. **No PyTorch. No external ML library. Pure Jac OSP — the graph itself is the learner.**

**3. Reflexion in pure Jac — the agent remembers its own past performance, stored as graph nodes.** After every chat turn a zero-LLM `CritiqueWalker` reads the walker chain telemetry (which walkers fired, did escalation occur, did Pathfinder find an escape route, how many eligible resources, estimated LLM-call count), computes a session quality score from a deterministic heuristic, and writes a `SessionInsight` node attached to the user's PersonNode via a `reflected_on` edge. On the next chat turn, IntakeWalker reads the two newest `SessionInsight` nodes back and **prepends their headlines as a plain-text context prefix** to the conversation the LLM sees — so the agent literally learns from its own past performance. This is [Reflexion](https://www.promptingguide.ai/techniques/reflexion) (Shinn et al, 2023; the most-cited 2026 self-improvement technique per the [agent-evaluation survey](https://arxiv.org/html/2503.16416v2)) implemented as **pure graph mutation in Jac**, with zero external memory store, zero vector database, zero PyTorch, and zero new LLM tokens. The agent's memory IS the graph. The Telemetry tab surfaces a rolling self-reflection chart showing the quality score trending across the user's chat history.

### The full pipeline

- **IntakeWalker** detects language, finds or creates a `PersonNode` reachable from `root`, and extracts a structured `NeedProfile` (category + urgency + free-form details) from the conversation.
- **EligibilityWalker** scores up to 6 seeded `ResourceNode`s against the profile using `check_eligibility()`, traversing `governed_by` edges to read each rule and weighting the result by the rule's learned `prior_success_rate`. When zero scores clear the threshold it spawns the **Pathfinder** before falling through to escalation.
- **PathfinderWalker** (NEW) — bounded BFS over `leads_to` edges. Discovers 1–3 multi-step escape paths the flat scorer can't see.
- **NavigationWalker** sequences eligible resources into an ordered `ActionPlan`, persists one `ApplicationNode` per recommended step on the `applied_to` edge, and returns the plan with summary + next action.
- **MemoryWalker** snapshots session state for return visits AND updates `prior_success_rate` on every ApplicationNode status change. The graph auto-persists everything reachable from `root` — refresh the browser, same session.
- **EscalationWalker** is a byllm ReAct loop with three tools (`check_emergency_resources`, `find_appeal_orgs`, `assess_safety_risk`) that fires only as a true last resort, when BOTH direct eligibility AND multi-hop pathfinding find nothing.
- **CritiqueWalker** (NEW) — Reflexion-style self-reflection. Fires after every chat turn, reads the chain telemetry with zero LLM cost, writes a `SessionInsight` node persisted via the `reflected_on` edge.
- **ReflectionReadWalker** (NEW) — companion read-only walker the Telemetry panel polls to render the rolling self-reflection chart.

Two utility walkers complete the system: **TranslateWalker** batch-translates the bot reply + suggestion chips into the detected language (with a session-level translation cache to stay inside free-tier LLM budgets), and **ImpactWalker** traverses every `PersonNode` and `ApplicationNode` to aggregate live dashboard stats — no mocks.

Every chat response shows the full reasoning trace: numbered step list with the walker that ran, the input it saw, the structured output it produced, and a one-paragraph reasoning prose explaining the choice. When the Pathfinder fires, escape-path cards render inline showing each `leads_to` hop with its `transition_reason`, `typical_days`, and `difficulty` payload.

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

- **Two genuinely novel Jac patterns** — (1) PathfinderWalker doing multi-hop BFS over a typed `leads_to` edge class to surface civic-aid escape paths when direct eligibility fails; (2) outcome-learning weights persisted as `prior_success_rate` on `EligibilityRuleNode` and updated by MemoryWalker. We searched the JacHacks 2026 winners gallery and prior published Jac demos — neither pattern appears anywhere else.
- **The Pathfinder solves a real civic problem.** Single mothers, undocumented families, and elderly tenants frequently *almost* qualify for a benefit but score 5–15 points below the threshold. Today, that's a dead-end "you don't qualify, sorry" experience. The Pathfinder turns those dead-ends into actionable multi-step pathways: Emergency Shelter intake produces a Section 8 priority application; food-pantry intake captures SNAP eligibility data; FQHC patient navigators submit Medicaid applications. We hand-curated 25+ real-world transitions across 4 categories and 5 cross-vertical bridges.
- **The graph that learns.** No PyTorch, no external ML library — `prior_success_rate` updates happen via Jac walker mutations on the graph itself. After 20 application outcomes a rule, the prior has ~50% weight in scoring. Demo: mark an application denied → next chat turn ranks the same prompt differently.
- **Multilingual end-to-end** — Tamil, Hindi, Spanish, Arabic, English all round-trip through the pipeline with the bot reply, suggestion chips, and reasoning trace all rendered in the user's detected language. EscalationWalker now generates `personalized_message` directly in the target language via `context.profile.language` so no English fragments leak from a second translation pass.
- **Transparent agent reasoning** — every response carries a step-by-step trace panel showing what each walker did, what it saw, what it output, and why. No "trust me" black box. Inline step-pills above each bubble (Perplexity Pro Search pattern) show the walker chain that produced THIS reply.
- **Real seeded resources** — 40 actual federal/state programs (Section 8, SNAP, WIC, LIHEAP, Medicaid, Catholic Charities, 211, etc.) with real phone numbers. Judges can google any name and find it.
- **Graph-native, not graph-decorative** — every node we create is reachable from `root` and persists across browser refresh. SeedWalker bootstraps per-user roots on first auth so jac-scale's multi-tenancy works transparently. Demo loop: chat → refresh → session loads.
- **Live graph visualization** — the Graph tab shows the real walker traversal frame-by-frame using events emitted by the chat pipeline, plus LiveTelemetryWalker streams per-class node counts (P·1 N·1 R·40 A·4) in the header strip. Hover any node for a per-walker tooltip explaining what that walker found there.
- **byllm-idiomatic LLM stubs** — every prompt is generated from `sem` strings on the parameter and return-type fields, so there are zero hand-crafted prompt templates anywhere in the codebase.
- **Cmd+K command palette** — keyboard-first navigation across all 5 tabs, with built-in actions for Replay, /docs OpenAPI, and Reset.
- **Cost-disciplined** — entire stack runs on NVIDIA NIM free tier with Featherless.AI configured as a fallback. Each chat turn caps at ~10 LLM calls (1 intake + 6 eligibility + 1 navigation + 1–2 translation). No paid voice/multimodal APIs. Deployable for free.

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

## The Jac features we actually use idiomatically (not just imported)

- **Walker abilities keyed by node type** — `can plan with PersonNode entry`, `can check with NeedNode entry`, `can escalate with PersonNode entry`. The walker chain reads as a graph traversal, not a function call sequence.
- **Typed edges with payload** — `edge leads_to { has transition_reason: str; has typical_days: int; has difficulty: str; }`. The Pathfinder reads payloads off the edges it traverses, not from a separate adjacency table.
- **Idiomatic `visit` over edge filters** — `[here ->:has_need:-> [?:NeedNode]]`, `[resource ->:governed_by:-> [?:EligibilityRuleNode]]`, etc. NavigationWalker uses multi-hop edge-filter chains in single expressions.
- **`disengage` for early termination** — EligibilityWalker disengages immediately after composing the report payload so we don't accidentally re-enter the walker on neighboring NeedNodes.
- **Per-user auto-persistence** — every node we create is reachable from the authenticated user's `root`. jac-scale handles the per-user multi-tenancy automatically; we just spawn `SeedWalker` once on auth to bootstrap the resource catalog into the fresh root.
- **WebSocket walker** — `@restspec(protocol=APIProtocol.WEBSOCKET)` on EscalationWalker streams ReAct iteration progress to the client.
- **`sem` strings everywhere** — 69 sem annotations on `llm/stubs.jac` alone, plus on every walker `has` field. byllm folds these into the prompt automatically. Zero hand-written prompt templates in the whole codebase.
- **Auto-generated OpenAPI** — jac-scale exposes every walker at `/walker/{Name}` with full schema at `/docs`. Cmd+K palette has a "Show /docs OpenAPI" action.
- **byllm ReAct loop with tools** — `by llm(method="ReAct", tools=[check_emergency_resources, find_appeal_orgs, assess_safety_risk])` for the EscalationWalker. The iteration callback caps the loop and streams progress.
- **Auto-built REST + WebSocket surface** — `jac start app.jac --dev` boots the agent + the client bundle + Vite HMR. No FastAPI, no Uvicorn, no manual routing.

---

Built for JacHacks Spring 2026.
