# CivicMesh

> CivicMesh — A multi-agent AI navigator that routes people in crisis to the housing, food, healthcare, and legal aid they qualify for. In any language. In under a minute.

## The problem

Tens of millions of vulnerable people — single mothers, undocumented families, elderly tenants on fixed incomes — do not know which programs they qualify for, what documents they need, or which agency to call first. Existing safety nets are real, but they are buried behind bureaucratic walls: fragmented websites, English-only intake forms, and screening logic that takes a caseworker to decode.

CivicMesh is a graph-native, multi-agent navigator built on Jac. A user types one sentence in any language and gets back a ranked, eligibility-checked, multilingual action plan in under a minute.

## Demo

![Landing](docs/landing.png)
![Chat and pipeline](docs/chat.png)
![Action plan](docs/action_plan.png)
![Graph view](docs/graph.png)
![Telemetry](docs/telemetry.png)

## How it works

A single user message enters the system and is processed by a chain of five walkers traversing a persistent graph of `PersonNode`, `NeedNode`, `ResourceNode`, and `OutcomeNode`. Two utility walkers (`TranslateWalker`, `ImpactWalker`) augment the chain.

```
                user message (any language)
                            |
                            v
                  +---------------------+
                  |   TranslateWalker   |  detect locale, normalize to English
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  |    IntakeWalker     |  byllm extracts PersonNode + NeedNodes
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  | EligibilityWalker   |  visit ResourceNodes, score qualifications
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  |  NavigationWalker   |  rank, sequence, generate next-step plan
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  |    MemoryWalker     |  persist session via root-reachable graph
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  |  EscalationWalker   |  detect urgency, surface human handoffs
                  +----------+----------+
                             |
                             v
                  +---------------------+
                  |   ImpactWalker      |  aggregate $/year + outcome telemetry
                  +---------------------+
                             |
                             v
                   translated response
```

The five-walker chain is the spine. `TranslateWalker` wraps the pipeline so the user can speak any language without us shipping a separate i18n layer. `ImpactWalker` reads the graph on demand to produce aggregate social-impact statistics.

## Built with

![Jac](https://img.shields.io/badge/Jac-0.x-7c3aed)
![Jaseci](https://img.shields.io/badge/Jaseci-runtime-1f6feb)
![byllm](https://img.shields.io/badge/byllm-LLM%20abilities-22c55e)
![jac-scale](https://img.shields.io/badge/jac--scale-REST%20%2B%20WS-0ea5e9)
![NVIDIA NIM](https://img.shields.io/badge/NVIDIA%20NIM-llama--3.1--8b--instruct-76b900)
![litellm](https://img.shields.io/badge/litellm-provider%20router-f59e0b)
![React](https://img.shields.io/badge/React-18-61dafb)

## Jac features showcased

- **Walkers with abilities keyed by node type.** Each walker declares `with PersonNode entry`, `with ResourceNode entry`, etc., so node-specific logic stays at the node boundary instead of branching inside the walker body.
- **Graph-native nodes and edges with `sem` strings.** Every node and edge type ships with a semstring describing its role; byllm reads those strings as grounding when it generates structured output.
- **`visit` with edge filters.** Traversal uses typed edge filters (`visit [-->](`edge type`)`) to constrain walks to the relevant slice of the graph (eg. `PersonNode` to eligible `ResourceNode`s only).
- **byllm with structured returns + ReAct + tools.** LLM-backed abilities return typed Jac objects, not free text. Where the model needs to look things up, it runs in ReAct mode with bound tools.
- **jac-scale auto REST/WS endpoints.** Every walker is exposed as both an HTTP endpoint and a WebSocket stream without us hand-writing any FastAPI glue. The OpenAPI spec is generated at `/docs`.
- **MemoryWalker session persistence via root-reachable graph.** Sessions live as subgraphs reachable from `root`; a browser refresh reloads the user's full conversation and plan without a database call.
- **TranslateWalker for any-language UX.** A wrapper walker handles locale detection on the inbound side and re-translation on the outbound side, so the entire pipeline stays English-internal while the user stays in their language.

## Quick start

Prerequisites:

- Python 3.12
- `jaclang` (installed via `requirements.txt`)
- An NVIDIA NIM API key (free tier works for the demo)

```bash
git clone https://github.com/Anbu-00001/CivicMesh.git
cd CivicMesh
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# edit .env and paste your key
export NVIDIA_NIM_API_KEY=nvapi-...

cd civicmesh
jac start app.jac --dev
```

The dev server binds two ports: `8000` serves the React client, `8001` serves the API and WebSocket. Open `http://localhost:8000/cl/app` in a browser.

## Environment variables

| Name | Required | Description |
| --- | --- | --- |
| `NVIDIA_NIM_API_KEY` | yes | NVIDIA NIM key used by byllm to call `meta/llama-3.1-8b-instruct`. |
| `FEATHERLESS_API_KEY` | no | Optional Featherless fallback provider used if NIM is unreachable. |
| `JAC_SCALE_HOST` | no | Override the host the API server binds to. Defaults to `127.0.0.1`. |
| `JAC_SCALE_PORT` | no | Override the API port. Defaults to `8001`. |
| `JAC_CLIENT_PORT` | no | Override the React client port. Defaults to `8000`. |
| `CIVICMESH_LOG_LEVEL` | no | `debug`, `info`, `warn`, `error`. Defaults to `info`. |

## Project structure

```
CivicMesh/
├── civicmesh/
│   ├── app.jac                  # entry point, wires the walker chain
│   ├── app.sv.jac               # server-side definitions
│   ├── frontend.cl.jac          # client shell + routing
│   ├── frontend.impl.jac        # client implementation
│   ├── walkers/
│   │   ├── intake.jac           # parse free-text into PersonNode + NeedNodes
│   │   ├── eligibility.jac      # score ResourceNodes against the person
│   │   ├── navigation.jac       # rank, sequence, build the action plan
│   │   ├── memory.jac           # persist session to root-reachable graph
│   │   ├── escalation.jac       # detect urgency, route to human handoff
│   │   ├── translate.jac        # locale wrap around the pipeline
│   │   └── impact.jac           # aggregate impact telemetry
│   ├── components/              # React-on-Jac UI (Chat, Graph, Plan, Telemetry, Impact)
│   ├── llm/
│   │   └── stubs.jac            # byllm ability declarations + semstrings
│   ├── graph/
│   │   ├── nodes.jac            # PersonNode, NeedNode, ResourceNode, OutcomeNode
│   │   ├── edges.jac            # typed edges with sem strings
│   │   └── seed_data.jac        # real seeded resources (SNAP, WIC, LIHEAP, ...)
│   ├── data/
│   │   └── resources.json
│   └── tests/
├── docs/
│   ├── DEMO_SCRIPT.md
│   └── DEVPOST_WRITEUP.md
├── requirements.txt
├── .env.example
└── LICENSE
```

## License

MIT. See [LICENSE](./LICENSE).

---

Built for JacHacks Spring 2026 · Anbu et al.
