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

## 1:30 – 2:05 — THE differentiator: Escape-Path Pathfinder

**On screen:** Back to the Chat tab. Send a deliberately edge-case prompt that won't directly qualify for housing.

**Action:** Type:
> "I'm 71 years old, my income is twenty-eight thousand a year from Social Security, my landlord is trying to evict me illegally."

**Voiceover (over the response):**
> "This one's hard. Twenty-eight thousand is too high for most income-tested housing programs but too low to absorb an illegal eviction. Watch what happens."

**Action:** Wait. EligibilityWalker scores its near-misses, then a cyan **PATHFINDER** pill lights up in the step-pills above the bubble. Three chained cyan cards render below.

**Voiceover:**
> "Direct eligibility scoring missed. Every project here today would stop there — escalate to a crisis hotline. CivicMesh does something different. The PathfinderWalker fires — bounded breadth-first search over a new `leads_to` edge type representing real-world civic-aid transitions."

**Action:** Point at the chained escape-path cards. Each card shows a from → to step with a difficulty pill and a typical-days estimate.

**Voiceover:**
> "Three escape paths, ranked by total time to resolution. Tenant Rights Hotline routes to Catholic Charities Emergency Rental Assistance — that pays the back rent and stops the eviction. From there, a 60-day path opens to Section 8 priority. The graph saw what the flat eligibility check could not. The civic safety net is a multi-step maze, and you navigate it with graph traversal, not keyword matching."

**Action:** Click the **Graph** tab. Cyan beam overlay along the discovered path.

**Voiceover:**
> "Here's the route, lit up on the actual graph. Multi-hop reasoning over a civic knowledge graph — the 2026 RAG frontier — applied to where it actually matters."

---

## 2:05 – 2:30 — The graph that learns

**On screen:** **Action Plan** tab. Hover over a pending application.

**Voiceover:**
> "Second innovation: the graph learns from outcomes. Every `EligibilityRuleNode` carries a Bayesian-style success prior."

**Action:** Mark an ApplicationNode "denied".

**Voiceover:**
> "MemoryWalker just walked back to the gating EligibilityRuleNode and updated its `prior_success_rate`. Next time someone with a similar profile asks a similar question, EligibilityWalker blends the raw LLM score with the learned prior. The graph is now slightly less likely to recommend that program."
>
> "No PyTorch. No external machine-learning library. Pure Jac walker mutations on a typed graph. The substrate itself is the learner."

---

## 2:30 – 2:45 — Jac-native rapid-fire

**On screen:** Open `http://localhost:8001/docs` in a second tab. Scroll briefly.

**Voiceover:**
> "Every walker is automatically a REST endpoint and a WebSocket stream. Zero FastAPI. The `sem` strings on every node, edge, and walker field auto-generate byllm prompts — no hand-written templates anywhere in the codebase."

**Action:** Switch back, hit Ctrl+Shift+R to hard-refresh.

**Voiceover:**
> "Refresh, and the entire session — PersonNode, NeedNodes, ApplicationNodes, the `leads_to` edges I added live — is still there. Everything reachable from the authenticated root auto-persists. The graph is the database."

---

## 2:45 – 2:55 — Social impact framing

**On screen:** Click the **Impact** tab.

**Voiceover:**
> "Live aggregate — every PersonNode and ApplicationNode in the graph, real-time. The dashboard a city housing department would actually use. CivicMesh isn't chatbot theater — it's real routing on real seeded resources, in any language, with graph-grounded reasoning."

---

## 2:55 – 3:00 — Call to action

**On screen:** Final card: CivicMesh logo, GitHub URL, JacHacks badge.

**Voiceover:**
> "Built on Jac in four days. Fully open source. CivicMesh, for JacHacks Spring 2026."

**Cut.**
