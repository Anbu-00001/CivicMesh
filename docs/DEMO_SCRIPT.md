# CivicMesh — 3-Minute Demo Script

Target length: 3:00. Recorded at 1080p, screen capture + voiceover. Cursor visible.

---

## 0:00 – 0:15 — Hook

**On screen:** CivicMesh landing page. Logo, hero line, single input field with a cursor blink.

**Voiceover:**
> "Every bureaucratic wall has a door. CivicMesh finds it."
>
> "This is a multi-agent AI navigator that routes vulnerable people to housing, food, and legal aid in any language — in under a minute."

**Action:** Hover over the input. Do not type yet.

---

## 0:15 – 0:45 — The real-world problem

**On screen:** Cut to a static slide with a persona photo and quote, then a stat card.

**Voiceover:**
> "Meet Maria. Single mother in Houston, two kids, eighteen hundred dollars a month, fluent in Spanish. She qualifies for SNAP, WIC, LIHEAP, and emergency housing assistance — but she does not know it."
>
> "More than forty million Americans are enrolled in SNAP alone. The number who qualify but never apply is in the millions. The reason is almost never eligibility. The reason is the wall: fragmented intake forms, English-only screening, no single agency that owns the routing."

**Action:** Fade the slide. Return to the CivicMesh landing.

---

## 0:45 – 1:30 — Live demo

**On screen:** CivicMesh chat. Pipeline sidebar visible on the right showing the five walkers as inactive dots.

**Voiceover:**
> "Let us put Maria's question into the box, in Spanish."

**Action:** Type:
> "Soy una madre soltera con dos hijos en Houston. Gano mil ochocientos al mes. Necesito ayuda con la vivienda."

**Voiceover (over the response):**
> "Watch the sidebar. TranslateWalker fires first — it detects Spanish, normalizes to English for the pipeline. Then IntakeWalker builds a PersonNode and two NeedNodes. EligibilityWalker visits every ResourceNode through typed edge filters and scores them. NavigationWalker ranks and sequences the plan. MemoryWalker writes the session to the graph. The whole chain ran in under a minute."

**Action:** Click the **Action Plan** tab.

**Voiceover:**
> "Here is the plan: SNAP, WIC, Houston Housing Authority Section 8, LIHEAP. Each step has the exact documents she needs and the office to call. The widget at the top estimates fifty-four hundred dollars a year in unlocked benefits."

**Action:** Click the **Graph** tab.

**Voiceover:**
> "This is the graph view. The traveling dots are the actual walker traversals — PersonNode out to NeedNodes, NeedNodes out to ResourceNodes through eligibility edges. This is not a visualization layer on top of the LLM. The LLM is grounded in the graph."

**Action:** Click the **Telemetry** tab.

**Voiceover:**
> "And per-walker telemetry: token counts, latency, which walker called which byllm ability. Full transparency on agent reasoning."

---

## 1:30 – 2:15 — Jac features highlight

**On screen:** Open `http://localhost:8001/docs` in a second tab.

**Voiceover:**
> "Every walker in CivicMesh is automatically a REST endpoint and a WebSocket stream. We did not write a single line of FastAPI. jac-scale generates this OpenAPI surface from the walker signatures."

**Action:** Scroll the OpenAPI page briefly. Switch to a code editor showing `walkers/intake.jac`.

**Voiceover:**
> "Here is IntakeWalker. The `with PersonNode entry` block is the node-keyed ability — node-specific logic lives at the node boundary. The `sem` strings on each node type are what byllm uses to ground its structured output. No hand-written prompts."

**Action:** Switch back to the browser. Hard-refresh the page.

**Voiceover:**
> "And because the session lives on the root-reachable graph, refresh — and Maria's full conversation, her PersonNode, her action plan, all of it, is still here. No database. The graph is the database."

---

## 2:15 – 2:45 — Social impact framing

**On screen:** Click the **Impact Report** tab.

**Voiceover:**
> "If we had a thousand PersonNodes in the graph — a thousand Marias — this is what it would look like. Aggregate dollars unlocked, top unmet needs by region, escalation rate. This is the dashboard a city housing department or a non-profit would actually use."
>
> "CivicMesh is not chatbot theater. It is real routing on real seeded resources, in any language, with transparent reasoning."

---

## 2:45 – 3:00 — Call to action

**On screen:** Final card: CivicMesh logo, GitHub URL, JacHacks badge.

**Voiceover:**
> "Built on Jac in four days. Fully open source. CivicMesh, for JacHacks Spring 2026."

**Cut.**
