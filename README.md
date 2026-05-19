<div align="center">

# CivicMesh

### A multi-agent AI navigator that routes people in crisis to the housing, food, healthcare, and legal aid they qualify for — in any language, in under a minute.

[![Jac](https://img.shields.io/badge/Jac-0.15-7c3aed?style=flat-square)](https://github.com/Jaseci-Labs/jaclang)
[![Jaseci](https://img.shields.io/badge/Jaseci-runtime-1f6feb?style=flat-square)](https://jaseci.org)
[![byllm](https://img.shields.io/badge/byllm-0.6.7-22c55e?style=flat-square)](https://github.com/Jaseci-Labs/byllm)
[![NVIDIA NIM](https://img.shields.io/badge/NVIDIA%20NIM-llama--3.1--8b-76b900?style=flat-square)](https://build.nvidia.com)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](./LICENSE)
[![JacHacks](https://img.shields.io/badge/JacHacks-Spring%202026-ff6b6b?style=flat-square)](https://jaseci.org)

</div>

---

## The problem

Tens of millions of vulnerable people — single mothers, undocumented families, elderly tenants on fixed incomes — do not know which programs they qualify for, what documents they need, or which agency to call first. The safety net is real, but it is buried behind fragmented websites, English-only intake forms, and screening logic that takes a caseworker to decode.

CivicMesh is a **graph-native multi-agent navigator** built on Jac. One sentence in any language → a ranked, eligibility-checked, multilingual action plan. With **phone numbers up front**.

---

## What makes it different

Three innovations no other Jac project has shipped:

| | Innovation | Why it matters |
|---|---|---|
| 🧭 | **Pathfinder** — multi-hop BFS over `leads_to` edges between resources | When a user doesn't qualify *directly*, the graph finds a 2-3 step escape route (e.g. *Emergency Shelter → Continuum of Care → Section 8*). Graph-RAG over a curated civic-aid knowledge graph. |
| 🧠 | **Outcome-Learning Eligibility** — Bayesian priors on `EligibilityRuleNode` | Every approved/denied `ApplicationNode` updates a Laplace-smoothed success prior on the gating rule. The graph **gets smarter every time someone uses it** — no PyTorch, no retraining, just Jac OSP. |
| 🔁 | **Reflexion self-reflection loop** | `CritiqueWalker` writes a `SessionInsight` after every turn; the next `IntakeWalker` reads the last two as conversation prefix. The agent literally **reads its own past performance as memory** — Shinn et al. (2023) implemented as native graph edges. |

---

## Architecture

```mermaid
flowchart TD
    User([👤 User · any language])
    Client[React-on-Jac client<br/>ChatPane · GraphViz · ActionPlan]

    User -->|chat turn| Client
    Client -->|spawn root walker| Intake

    subgraph Pipeline ["Walker chain · spawned per turn"]
        direction TB
        Intake[🚪 IntakeWalker<br/><i>detect lang · extract NeedProfile</i>]
        Elig[🎯 EligibilityWalker<br/><i>score 6 ResourceNodes · LLM</i>]
        Nav[📋 NavigationWalker<br/><i>sequence ActionPlan</i>]
        Path[🧭 PathfinderWalker<br/><i>multi-hop BFS</i>]
        Esc[🆘 EscalationWalker<br/><i>ReAct loop · WebSocket</i>]
        Crit[🪞 CritiqueWalker<br/><i>write SessionInsight</i>]
    end

    Intake -->|spawn| Elig
    Elig -->|matches ≥ threshold| Nav
    Elig -->|0 matches| Path
    Path -->|0 paths| Esc
    Elig -.->|fire-and-forget| Crit
    Nav -.->|fire-and-forget| Crit

    subgraph Graph ["Persistent graph · reachable from root"]
        direction LR
        Person((PersonNode))
        Need((NeedNode))
        Resource((ResourceNode))
        Rule((EligibilityRuleNode))
        Form((FormNode))
        App((ApplicationNode))
        Insight((SessionInsight))
    end

    Intake --> Person
    Person --> Need
    Resource --> Rule
    Rule --> Form
    Nav --> App
    Crit --> Insight

    Nav --> Client
    Path --> Client
    Esc --> Client

    classDef walker fill:#7c3aed,stroke:#5b21b6,color:#fff,stroke-width:2px
    classDef nodecls fill:#1f6feb,stroke:#1e40af,color:#fff
    classDef ui fill:#22c55e,stroke:#15803d,color:#fff
    class Intake,Elig,Nav,Path,Esc,Crit walker
    class Person,Need,Resource,Rule,Form,App,Insight nodecls
    class Client,User ui
```

The chain is **lazy-branching**: EligibilityWalker only spawns NavigationWalker if matches exist, only spawns PathfinderWalker on a dead end, and only spawns EscalationWalker if Pathfinder also fails. CritiqueWalker fires at the end regardless — the post-turn self-reflection is mandatory.

---

## Walker path · the happy path

A typical successful turn — *"I'm a single mom, need help with rent, two kids, $1,200/month"* — traces this exact path through the graph:

```mermaid
sequenceDiagram
    autonumber
    participant U as User
    participant I as IntakeWalker
    participant LLM as byllm pool<br/>(NIM llama-3.1-8b)
    participant E as EligibilityWalker
    participant N as NavigationWalker
    participant C as CritiqueWalker
    participant G as Graph (root)

    U->>I: "Necesito ayuda con el alquiler"
    I->>G: read past SessionInsights (Reflexion)
    G-->>I: 2 prior headlines
    I->>LLM: detect_language(raw prompt)
    LLM-->>I: lang="es"
    I->>LLM: extract_need_profile(augmented)
    LLM-->>I: NeedProfile(housing, immediate, ...)
    I->>G: ++> NeedNode via has_need edge
    I->>E: spawn(profile, person_node)

    loop 6 ResourceNodes
        E->>G: traverse governed_by → EligibilityRuleNode
        E->>LLM: check_eligibility(profile, rule)
        LLM-->>E: EligibilityResult(score, matched, missing)
        E->>E: blend with prior_success_rate (outcome learning)
    end

    E->>N: spawn(eligible, possible, profile)
    N->>G: traverse requires_form → FormNode
    N->>LLM: generate_action_plan(eligible_names)
    LLM-->>N: ActionPlan(steps)
    N->>G: ++> ApplicationNode per step

    I->>C: spawn(chain events, outcomes)
    C->>G: ++> SessionInsight via reflected_on edge

    N-->>U: ranked plan · translated to es · with phone numbers
```

---

## Graph schema

Every node and edge ships with a `sem` semstring; byllm reads those strings as grounding when generating structured output, so the schema *is* the prompt context.

```mermaid
erDiagram
    PersonNode ||--o{ NeedNode : "has_need"
    PersonNode ||--o{ ApplicationNode : "applied_to"
    PersonNode ||--o{ SessionInsight : "reflected_on"
    NeedNode ||--o{ ResourceNode : "matches (category)"
    ResourceNode ||--|| EligibilityRuleNode : "governed_by"
    EligibilityRuleNode ||--|| FormNode : "requires_form"
    ResourceNode ||--o{ ResourceNode : "leads_to (multi-hop)"

    PersonNode {
        str user_id
        str language
        str location_zip
        str income_bracket
        int family_size
    }
    NeedNode {
        str category
        str urgency
        str details
    }
    ResourceNode {
        str agency_name
        str category
        str capacity
        str contact_phone
        list languages_supported
    }
    EligibilityRuleNode {
        str criteria_summary
        int income_limit_annual
        bool citizenship_required
        float prior_success_rate
        int prior_attempts
        int prior_approvals
    }
    FormNode {
        str form_name
        list required_documents
        str deadline_type
        int estimated_minutes
    }
    ApplicationNode {
        str application_id
        str status
        str resource_name
        str denial_reason
    }
    SessionInsight {
        str ts
        str headline
        int quality_score
        list walkers_fired
    }
```

---

## Dead-end recovery · Pathfinder

When EligibilityWalker scores **zero** matches above threshold, we don't drop straight to crisis. Pathfinder runs BFS over the typed `leads_to` edge — 25+ curated real-world resource transitions (DV Hotline → Emergency Shelter → Section 8, SNAP intake → WIC pre-qualification, etc.) — to discover **multi-step escape paths**:

```mermaid
flowchart LR
    seed[Seed: near-miss<br/>resources from<br/>EligibilityWalker]
    start([User's category])

    start --> bfs{BFS over<br/>leads_to edges<br/>max_hops=3}
    seed --> bfs

    bfs -->|hop 1| r1[Emergency<br/>Shelter<br/>Network]
    r1 -->|7 days · easy| r2[Continuum<br/>of Care]
    r2 -->|90 days · medium| r3[Section 8<br/>HCV priority]

    bfs -->|hop 1| h1[DV Hotline]
    h1 -->|same-day · easy| h2[Safe-house<br/>placement]

    r3 --> out([Up to 3 paths<br/>ranked by<br/>total_days + hops])
    h2 --> out

    classDef seed fill:#fbbf24,stroke:#d97706,color:#000
    classDef resource fill:#0ea5e9,stroke:#0369a1,color:#fff
    classDef out fill:#22c55e,stroke:#15803d,color:#fff
    class start,seed seed
    class r1,r2,r3,h1,h2 resource
    class out,bfs out
```

This is **graph-RAG** applied to social services — the 2026 RAG frontier, native to Jac, with zero external vector store.

---

## Outcome learning · the graph gets smarter

Every terminal `ApplicationNode.status` update (`approved` or `denied`) walks back to the gating `EligibilityRuleNode` and updates a **Laplace-smoothed Bayesian prior**. Subsequent EligibilityWalker calls blend the raw LLM `match_score` with that prior, weighted by `attempts / (attempts + 20)`:

```mermaid
flowchart TD
    A[User marks app<br/>'approved' or 'denied'] --> B[MemoryWalker<br/>update_status mode]
    B --> C[Walk back to<br/>EligibilityRuleNode<br/>via governed_by]
    C --> D["Update priors:<br/>attempts += 1<br/>approvals += approved?1:0<br/>rate = (a+1)/(t+2)"]
    D --> E[(Graph)]
    E --> F[Next EligibilityWalker<br/>turn for any user]
    F --> G["adjusted_score =<br/>(1-blend)·llm + blend·prior·100<br/>where blend = t/(t+20)"]
    G --> H[Better ranked<br/>plan for next user]
    H -.->|over time| E

    classDef store fill:#1f6feb,stroke:#1e40af,color:#fff
    classDef walker fill:#7c3aed,stroke:#5b21b6,color:#fff
    class E store
    class B,F walker
```

Pure Jac OSP. No PyTorch, no fine-tuning, no offline batch job — the **graph itself is the model**.

---

## Reflexion · the agent reads its own past

After every turn, `CritiqueWalker` writes a `SessionInsight` node with a diversified headline (category prefix · resource named · quality score). The next `IntakeWalker` for the same user reads the most recent two as a conversation prefix — the agent literally **uses its own past performance as memory**, Shinn et al. (2023) implemented in 80 lines of Jac.

```mermaid
stateDiagram-v2
    [*] --> Turn_N
    Turn_N: Turn N · user message
    Turn_N --> Intake_N
    Intake_N: IntakeWalker reads<br/>last 2 SessionInsights<br/>as conversation prefix
    Intake_N --> Chain_N
    Chain_N: Eligibility → Navigation<br/>or → Pathfinder<br/>or → Escalation
    Chain_N --> Critique_N
    Critique_N: CritiqueWalker writes<br/>new SessionInsight<br/>with quality_score
    Critique_N --> [*]: turn complete

    [*] --> Turn_NP1
    Turn_NP1: Turn N+1 · same user
    Turn_NP1 --> Intake_NP1
    Intake_NP1: reads Critique_N's<br/>SessionInsight
    Intake_NP1 --> Chain_NP1
    Chain_NP1: chain uses<br/>last-turn context
    Chain_NP1 --> [*]
```

Telemetry tab renders a rolling chart of `quality_score` over time so judges can watch the agent improve in real time.

---

## Multi-language UX

The whole pipeline is **English-internal**. A user types in Spanish / Hindi / Tamil / Vietnamese / Bengali — `IntakeWalker` detects language on the **raw prompt** (never on the Reflexion-prefixed augmented input — that contaminated detection in early builds), and the final bot reply + suggestion chips are translated in **one batched LLM call** with a session-level translation cache so repeat strings never re-hit the model.

```mermaid
flowchart LR
    A["Necesito un<br/>refugio esta noche"] -->|raw| B[detect_language_and_extract]
    B -->|lang=es| C[extract_need_profile<br/>augmented w/ Reflexion]
    C --> D[Eligibility · Navigation<br/>all internal English]
    D --> E[bot_text<br/>suggestion_chips<br/>action_step descriptions]
    E -->|batched| F[translate_batch<br/>cached]
    F --> G["Llama al 1-800-799-7233<br/>Refugio inmediato disponible..."]

    classDef src fill:#fbbf24,stroke:#d97706,color:#000
    classDef out fill:#22c55e,stroke:#15803d,color:#fff
    classDef llm fill:#7c3aed,stroke:#5b21b6,color:#fff
    class A src
    class G out
    class B,C,D,F llm
```

---

## Jac features showcased

- **Walkers with abilities keyed by node type.** Each walker declares `with PersonNode entry`, `with NeedNode entry`, `with ResourceNode entry`, so node-specific logic stays at the node boundary.
- **Typed edges with payload.** `leads_to`, `applied_to`, `governed_by`, `reflected_on`, `has_need` — all carry typed `has` fields (transition_reason, difficulty, status, ts).
- **Edge-filter traversal expressions.** `[root --> [?:PersonNode, user_id == self.user_id]]` and chained walks like `[resource ->:governed_by:-> [?:EligibilityRuleNode]]` express multi-hop joins in one line.
- **byllm with structured returns + ReAct + tools.** LLM-backed abilities return typed Jac objects (`NeedProfile`, `EligibilityResult`, `ActionPlan`). `EscalationWalker` runs ReAct with three live-graph tools.
- **`sem` strings everywhere.** Every node, edge, walker field, and stub parameter ships a semstring — byllm uses these as the entire prompt context, so the schema *is* the system prompt.
- **jac-scale auto REST + WebSocket.** Walkers are exposed as both an HTTP endpoint and a streamed WebSocket without one line of FastAPI glue. `@restspec(protocol=APIProtocol.WEBSOCKET)` on EscalationWalker streams each ReAct step live.
- **Root-reachable session persistence.** Sessions live as subgraphs reachable from `root`; a browser refresh reloads the user's full conversation, plan, and applications with zero database calls.
- **`spawn` chaining with `.summary` mirroring.** Child walkers mirror their final `report` payload to `.summary` so the parent walker can read it back — because `report` only bubbles to the outermost walker's stream.

---

## Quick start

**Prerequisites:** Python 3.12 · an [NVIDIA NIM](https://build.nvidia.com) API key (free tier works).

```bash
git clone https://github.com/Anbu-00001/CivicMesh.git
cd CivicMesh

python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# paste your NVIDIA NIM key into .env
export NVIDIA_NIM_API_KEY=nvapi-...

cd civicmesh
jac serve app.jac
```

Then open **http://localhost:8000/cl/app** in a browser. The dev server binds `:8000` for the React client and `:8001` for the REST + WebSocket API. OpenAPI docs at `:8001/docs`.

### Try it

| Prompt | What fires |
|---|---|
| *"I'm a single mom, need help with rent, two kids"* | Intake → Eligibility → **Navigation** (action plan) |
| *"Necesito un refugio esta noche"* | Intake (es) → Eligibility → Navigation in Spanish |
| *"Who do I call for a domestic-violence safe house?"* | Intake → Eligibility → Navigation with **1-800-799-7233** up front |
| *"I'm being evicted tomorrow, nothing has worked"* | Intake → Eligibility (0 matches) → **Pathfinder** (multi-hop escape) |

---

## Environment variables

| Name | Required | Description |
|---|---|---|
| `NVIDIA_NIM_API_KEY` | yes | byllm key for `meta/llama-3.1-8b-instruct` |
| `FEATHERLESS_API_KEY` | no | Optional fallback provider |
| `JAC_SCALE_HOST` | no | API bind host. Default `127.0.0.1` |
| `JAC_SCALE_PORT` | no | API port. Default `8001` |
| `JAC_CLIENT_PORT` | no | React client port. Default `8000` |
| `CIVICMESH_LOG_LEVEL` | no | `debug` · `info` · `warn` · `error` |

---

## Project structure

```
CivicMesh/
├── civicmesh/
│   ├── app.jac                # entry point, exposes walkers as endpoints
│   ├── app.sv.jac             # server-side bindings
│   ├── frontend.cl.jac        # React client shell + routing
│   ├── frontend.impl.jac      # client implementation
│   ├── walkers/
│   │   ├── intake.jac         # language detect · NeedProfile extract · Reflexion read
│   │   ├── eligibility.jac    # score 6 ResourceNodes · outcome-learning blend
│   │   ├── navigation.jac     # ActionPlan generation · ApplicationNode persist
│   │   ├── pathfinder.jac     # multi-hop BFS over leads_to edges
│   │   ├── escalation.jac     # ReAct loop · WebSocket streaming
│   │   ├── critique.jac       # Reflexion write · SessionInsight headline
│   │   ├── memory.jac         # read_session · update_status · prior backfill
│   │   ├── translate.jac      # batched translation with session cache
│   │   ├── impact.jac         # aggregate dashboard stats
│   │   ├── live_telemetry.jac # real-time walker-event stream
│   │   └── seed.jac           # idempotent graph seeding + migration sweep
│   ├── components/
│   │   ├── ChatPane.{cl,impl}.jac
│   │   ├── ActionPlan.{cl,impl}.jac
│   │   ├── GraphViz.{cl,impl}.jac
│   │   ├── ImpactReport.{cl,impl}.jac
│   │   ├── TelemetryPanel.{cl,impl}.jac
│   │   ├── LandingPage.{cl,impl}.jac
│   │   └── SessionBanner.cl.jac
│   ├── llm/
│   │   └── stubs.jac          # byllm ability declarations + sem strings
│   ├── graph/
│   │   ├── nodes.jac          # PersonNode · NeedNode · ResourceNode · ...
│   │   ├── edges.jac          # has_need · governed_by · leads_to · reflected_on
│   │   └── seed_data.jac      # demo seed wiring
│   ├── data/
│   │   └── resources.json     # 40 curated US safety-net programs
│   ├── tests/
│   └── jac.toml
├── docs/
│   ├── DEMO_SCRIPT.md         # 3-min judge walkthrough
│   └── DEVPOST_WRITEUP.md     # full DevPost narrative
├── assets/                    # screenshots, badges
├── requirements.txt
├── .env.example
├── .gitignore
├── LICENSE
└── README.md
```

---

## License

MIT. See [LICENSE](./LICENSE).

---

<div align="center">

**Built for JacHacks Spring 2026** · *the safety net is real, it just needs a router*

</div>
