---
title: CivicMesh
emoji: 🏛️
colorFrom: blue
colorTo: green
sdk: docker
app_port: 7860
pinned: false
---

<div align="center">

# CivicMesh

### A multi-agent navigator that routes people in crisis to the housing, food, healthcare and legal aid they qualify for — answered in under a second, in the user's own language, against 2026 federal rules.

[![JacHacks Spring 2026 – 1st Place Agentic AI](https://img.shields.io/badge/JacHacks%20Spring%202026-1st%20Place%20Agentic%20AI-FFD700?style=for-the-badge)](https://devpost.com/software/civicmesh-0ctxl5)
[![JacHacks Spring 2026 – Best Startup Idea](https://img.shields.io/badge/JacHacks%20Spring%202026-Best%20Startup%20Idea-FFD700?style=for-the-badge)](https://devpost.com/software/civicmesh-0ctxl5)

[![Live demo](https://img.shields.io/badge/Live%20demo-Hugging%20Face%20Spaces-yellow?style=flat-square)](https://huggingface.co/spaces/Anbu-00001/CivicMesh)
[![Devpost](https://img.shields.io/badge/Devpost-CivicMesh-003e54?style=flat-square)](https://devpost.com/software/civicmesh-0ctxl5)
[![Jac](https://img.shields.io/badge/Jac-0.15-7c3aed?style=flat-square)](https://github.com/Jaseci-Labs/jaclang)
[![byllm](https://img.shields.io/badge/byllm-0.6.7-22c55e?style=flat-square)](https://github.com/Jaseci-Labs/byllm)
[![NVIDIA NIM](https://img.shields.io/badge/NVIDIA%20NIM-translation%20%2B%20narration-76b900?style=flat-square)](https://build.nvidia.com)
[![Languages](https://img.shields.io/badge/languages-111%20supported%20%C2%B7%2075%20instant-2563eb?style=flat-square)](#languages-and-dialects)
[![Eval](https://img.shields.io/badge/eval-352%20cases%20%C2%B7%20764%20checks-16a34a?style=flat-square)](#evaluation-and-hard-tests)
[![CI](https://github.com/Anbu-00001/CivicMesh/actions/workflows/ci.yml/badge.svg)](https://github.com/Anbu-00001/CivicMesh/actions/workflows/ci.yml)
[![Privacy](https://img.shields.io/badge/privacy-scrubbed%20%C2%B7%20deletable%20%C2%B7%20no%20tracking-0f766e?style=flat-square)](./PRIVACY.md)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](./LICENSE)

**JacHacks Spring 2026 — 1st Place, Agentic AI Track · Best Startup Idea** · [Devpost](https://devpost.com/software/civicmesh-0ctxl5) · [Live demo](https://huggingface.co/spaces/Anbu-00001/CivicMesh)

</div>

---

## The problem

Millions of people — single parents, immigrant families, elderly tenants on fixed incomes — don't know which programs they qualify for, what documents to bring, or which office to call first. The safety net is real, but it sits behind fragmented websites, English-only forms and screening rules that take a caseworker to decode.

CivicMesh turns one message, in the person's own words and language, into a ranked, explainable action plan. It is checked against the 2026 federal rules for *that* household, lists phone numbers first (including real local offices), and gives a plain-language reason for every recommendation.

## What makes it different

**Math first, LLM last.** Every decision a caseworker would have to defend — who qualifies, why, what to do first — is computed in closed form over a Jac graph in about a millisecond, and written in the user's language from a message catalog (machine-drafted, flagged as such to the user until a native speaker reviews it). Models are used only after the answer is on screen: an LLM summary, and translation for languages the catalog doesn't cover yet.

| Capability | What it does |
|---|---|
| **Answers composed in 51 languages, 111 supported** | The whole answer — programs, next step, the follow-up question, its quick replies, the chips, card labels and crisis lines — is composed in the user's language on the first response from a per-language message catalog: nothing to translate, time out or rate-limit. 75 languages are routed without an LLM; income, household, age, status and location are read in 21 of them. **NVIDIA Riva Translate** / **Gemma 4** translate for the rest; an **interpreter card** covers spoken-only languages such as Mam and K'iche'. |
| **Effective-dated 2026 policy table** | Income limits per household from HHS poverty guidelines, and HUD's own FY2026 Section 8 limits for the metro area of 106 cities (a national estimate, labeled as such, elsewhere); state Medicaid expansion; the 2025 immigrant-eligibility law with its dates; a USDA-formula SNAP estimate. Every criterion cites its source. |
| **Calibrated, explainable eligibility** | Hard gates × weighted soft criteria, capped at 97%. Thin evidence yields "needs info" rather than a guess. Near-misses get the smallest change that would qualify ("with a household of 4 or more"). |
| **One sharp follow-up question** | The value-of-information question that changes the most matches, with quick replies. |
| **Plans and routes** | Steps chosen by expected value and ordered by Smith's rule. Longer-term routes use Yen's k-shortest paths over typed `leads_to` edges. |
| **Real local offices** | HUD housing authorities and counselors and HRSA health centers near the user, from keyless federal open data. |
| **The graph is the product** | Each verdict is a scored `eligible_for` edge. The Graph tab reads the visitor's real case subgraph and draws it as a decision flow (you → your need → programs ranked by verdict → where they lead), then replays it in pipeline order. |
| **Safety by construction** | Crisis and violence flags that negation can't cancel, plus an escalate-only second layer for indirect wording ("everyone would be better off without me", "he controls my money"). **Quick exit** (button or Shift ×3) and a private session that crisis turns switch on, so a shared phone keeps nothing. A numbers guard on every model output. No default admin accounts. |
| **Private by design** | No sign-up and no name needed. What you type is read on the server and never stored or sent to any AI model: only the engine's reading is kept (kind of help, urgency, household, income). Server logs hold no user text, and **Delete my data** erases the case. Each of these is a test. [Privacy notice](./PRIVACY.md) |

---

## What an AI code review found, and what changed

In September 2026 the author asked a chat model (an AI assistant, not a human expert, and not an audit) to review the repository. It cloned the code, read the commit history and the engine and walker files, and checked the README's claims against them. What it praised and what it criticized are summarized below, with what changed. A chat model's score isn't a measurement, so none is quoted.

**What held up**

- **Not a thin LLM wrapper.** A real graph-and-walker architecture, built over months of commits.
- **"The single best decision in the project."** Per-program LLM eligibility judgments were replaced by a deterministic, closed-form engine: logistic income thresholds, Beta-Binomial approval odds, information-gain follow-up questions and Yen's k-shortest routes, with "no LLM on this path". In the review's words, it is *"recognizing where an LLM is a liability, not a feature."*
- **Hard-coded crisis handling.** 988 and the domestic-violence hotline are routed in code, so a crisis response can never be improvised by a model: *"the correct engineering instinct for this domain."*
- **Real domain data.** 40 programs, 10 per category, with real agencies and phone numbers, cited 2026 HHS poverty guidelines, HUD area median income, and the legislation by section.
- **A real adversarial suite,** aimed at the ways a keyword parser breaks: negation ("we're not homeless") and cross-category traps.
- **Security hygiene.** No leaked keys, a blank `.env.example`, and a system password randomized on every boot.

**What was missing, and what was done about it**

| The criticism | What changed | Where to check |
|---|---|---|
| Built on Jac, a pre-1.0 language few people use; nobody else can maintain it | A written maintenance plan. The engine, where every eligibility decision lives, is transpiled to plain Python on every push and passes the same 784 checks with no Jac installed. `jac eject` was verified for the whole app. Every package is pinned, and Dependabot opens tested upgrade PRs | [docs/MAINTENANCE.md](./docs/MAINTENANCE.md) · `tools/eject_engine.sh` · CI job `portable` |
| No CI | GitHub Actions on every push and PR: the eval and unit checks, the plain-Python engine, the external check on real posts (reported, not gating), and the production Docker image with 64 HTTP checks and a scan of the server logs for user text | [.github/workflows/ci.yml](./.github/workflows/ci.yml) |
| No privacy story, for users asked about immigration status, income, violence and self-harm | A [privacy notice](./PRIVACY.md) where every statement maps to a test. What users type is never stored and never sent to a model (below). **Delete my data** erases the case. jaclang's `report` had been printing every answer into the server logs; that echo is off | `engine/privacy.jac` · `walkers/forget.jac` · `walkers/log_privacy.jac` · E2E P1–P14 |
| Machine-drafted translations shown to vulnerable people | **0 of 50 are reviewed** (Spanish included). Until they are, each follows HHS Section 1557 guidance for unreviewed machine translation: a notice in the user's language, the English original one tap away, the English sentence under every crisis line, numbers locked by a test, and a report-a-mistake form | [docs/TRANSLATION_REVIEW.md](./docs/TRANSLATION_REVIEW.md) · `tools/review_sheet.py` |
| No evidence it holds up with a real person in crisis | Still true. The honest next step is a supervised pilot with a legal-aid clinic, library or 211 partner, where a caseworker reads every answer. Until then, the external check below measures the router on real people's words instead of the author's | — |

**A second pass that probed instead of reading, and what it found**

- *"I don't have a social security number"* marked a mother of three as a senior, because the lexicon read any "social security" as age 60+. That doubled her P(eligible) for two seniors-only programs, from 32% to 64%. Probing that class of bug found more: 22 of 65 new checks failed on the first run. One cause was that negation built for needs ("I have food stamps" means you don't need them) had been applied to personal facts, so "I have a son" and "I have nowhere to sleep" were dropped while "I don't have a disability" was kept. Words in their other senses were also counted: the Salvation Army, serving tables, a car parked on the street, substance-abuse treatment, "my back hurts me", an injury at work. All were fixed in the lexicon, never by editing a case. The suite that catches them is `golden_probes.json`, with `p_max` checks that fail when a wrong flag moves a probability.
- The identifier scrubber missed 11 of 17 realistic identifiers: names without "my name is", spelled-out birth dates, "+52" numbers, a landlord's or a child's name. The fix that closes the whole class was to stop depending on it. The narrator no longer receives the message, the stored need is the engine's reading, the stored self-critique no longer keeps a snippet of the message, and the routing fallback that sent unroutable messages to NVIDIA is off unless an operator opts in. The scrubber was widened anyway, and `tests/check_privacy.jac` prints what it still misses.
- The review cautioned against optimizing for a reviewer's checklist. That's why the next section measures against data nobody on this project wrote.

**A third pass, and a bug from real use**

- **A stuck chat, reported by a person using the live Space.** Four turns into a conversation ("I'm 72… evict me illegally" → "I live in illinois" → "There are 3 people…" → "Yes" to the disability question), the typing dots never went away and the Graph tab showed a raw error page. The live logs showed Hugging Face's Spaces proxy failing requests across many unrelated Spaces at the time: 502, 503 and 504 on the home page of several large public Spaces, while HF's status page still said "operational". The app still handled it badly, and replaying the conversation turned up three engine bugs:
  - **No timeout.** A request the proxy never answered locked the chat for good. There is now a 30-second timeout with **Try again**. The Graph tab retries by itself and shows a sentence instead of HTML. Every walker call now catches errors (six call sites could throw uncaught).
  - **Lost seeding.** One visitor's program catalog was never seeded, so every answer was empty. IntakeWalker now seeds an empty catalog itself.
  - **The engine bugs:** "There are 3 people" was read as a household of 0. A "Yes" to the disability question never set the flag. And the scorer's own situation checks matched raw words without negation, so "we're not homeless" made the emergency-shelter program *likely*, "the Salvation Army shelter" pushed veterans' housing to 62%, and "I don't have a disability" made disability legal aid *likely*. Person facts now have one source of truth: the parser's flags.
- **Indirect crisis wording.** The review wrote 16 indirect messages and the engine caught 0. An escalate-only second layer now reads the 988 Lifeline's and the Domestic Violence Hotline's published warning signs. On 14 indirect messages it went from 0 to 14. These are the author's sentences, so treat that as a regression guard, not a recall measurement. A concern pins the hotline as a gentle first line without switching the turn into crisis mode.
- **Device safety for survivors.** **Quick exit** follows GOV.UK's "Exit this page" pattern: a button or Shift ×3 jumps to a neutral site, and Back doesn't return. Crisis turns switch on a private session: the login lives only in the tab, the browser is wiped when it closes, and Quick exit also erases the case on the server.
- **Metamorphic testing.** Appending a sentence that says nothing about eligibility must not move any verdict (tier, or P(eligible) by more than 10 points). The current engine passes 228/228. The version the review tested fails 28, including the reported "needs info 43% → likely 85%", so this test would have found that bug without anyone thinking of the sentence.
- **Local income limits.** The engine used one national Section 8 limit ($53,950 for a family of 4). HUD sets it per metro area: $50,300 in San Antonio, $63,400 in Fort Lauderdale, $105,050 in San Francisco. `data/hud_income_limits.json` is built from HUD's FY2026 file for the 106 cities the parser knows.
- **Honest numbers and closed holes.** Approval odds are labeled a rough guess, with no fake interval, because they come from pseudo-counts, not outcomes. The narrator only accepts facts the server signed, so it can't be used as a free relay to the model quota. `SECURITY.md`, `CONTRIBUTING.md` and `CODEOWNERS` were added.
- **Not done:** an independent oracle check (PolicyEngine US), a stateless in-browser engine, last-verified dates on the 40 programs, legal review of the immigrant-eligibility rules, a second maintainer, native review, and a real pilot. Those need time or people outside this repository.


---

## Architecture

```mermaid
flowchart LR
    U([Person · any language]):::ui --> C[React-on-Jac client<br/>chat · graph · plan · impact]:::ui

    subgraph CP["Critical path — deterministic, ~1 ms engine · 0 LLM calls"]
        direction TB
        I[IntakeWalker<br/>language ID · parse · evidence spans]:::det
        E[EligibilityWalker<br/>2026 policy table · tiers · Beta odds]:::det
        N[NavigationWalker<br/>value-selected, Smith-ordered plan]:::det
        P[PathfinderWalker<br/>Yen k-shortest routes]:::det
        X[EscalationWalker<br/>crisis lines, never negated]:::safety
        K[CritiqueWalker<br/>self-critique from the trace]:::det
        MC[Message catalog<br/>answer · question · chips · labels<br/>in 51 languages]:::det
        I --> E --> N
        E --> P
        E --> X
        I --> K
        E --> MC
    end

    subgraph BG["After the answer is on screen"]
        direction TB
        T[LocalizeWalker<br/>translation, only without a catalog]:::mt
        R[NarrateWalker<br/>summary in the user's language]:::llm
        L[LocalHelpWalker<br/>offices near the user]:::ext
    end

    subgraph G["Per-visitor graph under root"]
        direction TB
        PN((Person)):::data --> ND((Need)):::data
        ND -->|eligible_for · tier · p| RS((Program)):::data
        RS --> RU((Rule)):::data
        RU --> FM((Form)):::data
        PN --> AP((Application)):::data
        PN --> SI((SessionInsight)):::data
    end

    C -->|spawn| I
    CP -.writes nodes + scored edges.-> G
    C -.background.-> T
    C -.background.-> R
    C -.background.-> L
    T --> RT[NVIDIA Riva Translate v2]:::mt
    T --> GM[Gemma 4 31B · NIM]:::llm
    R --> GM
    L --> OD[HUD + HRSA open data]:::ext

    classDef ui fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef safety fill:#fee2e2,stroke:#dc2626,color:#450a0a
    classDef llm fill:#ede9fe,stroke:#7c3aed,color:#2e1065
    classDef mt fill:#fae8ff,stroke:#a21caf,color:#4a044e
    classDef ext fill:#fef3c7,stroke:#d97706,color:#451a03
    classDef data fill:#dcfce7,stroke:#16a34a,color:#052e16
    style CP fill:#eff6ff,stroke:#93c5fd
    style BG fill:#f5f3ff,stroke:#c4b5fd
    style G fill:#f0fdf4,stroke:#86efac
```

**How to read it:**
- **Blue** is the deterministic critical path: the answer is computed, written in the user's language from the message catalog, and on screen before any model runs.
- **Purple and magenta** are the model calls, made in the background: the summary, and translation for the 34 languages without a catalog yet.
- **Amber** is live federal open data.
- **Green** is what gets persisted: every verdict and plan step is a node or typed edge under the visitor's own root.

### One chat turn

```mermaid
sequenceDiagram
    autonumber
    participant B as Browser
    participant I as IntakeWalker
    participant E as Engine (parse · policy · score · plan · paths)
    participant G as Graph
    participant T as Riva Translate / Gemma 4
    participant L as Narrator LLM
    participant O as HUD / HRSA open data

    rect rgb(219, 234, 254)
    Note over B,G: Critical path — no model calls
    B->>I: message (+ case so far, picked language)
    I->>E: language ID, need, facts, negation (~1 ms)
    Note over I,E: if nothing routes: ask what they need (quick replies) — the words are never sent to a model
    E->>E: 2026 limits for this household · tiers · Beta odds · next question
    E->>E: compose answer, question, quick replies, chips, labels in the user's language (catalog)
    E->>G: NeedNode, eligible_for edges, ApplicationNodes, SessionInsight
    I-->>B: answer, cards, plan, routes, trace (~0.2–0.5 s round trip)
    end

    rect rgb(237, 233, 254)
    Note over B,O: Background — the answer is already on screen
    par only for languages without a catalog
        B->>T: translate answer + short strings (numbers guarded)
        T-->>B: translated answer
    and summary
        B->>L: facts → 2–3 sentence summary
        L-->>B: summary (numbers guarded)
    and local offices
        B->>O: city / state
        O-->>B: housing authorities, counselors, health centers
    end
    end
```

The shaded blue block is everything the person waits for, and it involves no model. In 51 languages it already arrives in the person's language. The purple block runs in parallel afterwards. If a model is slow or down, the person still has the complete deterministic answer, in their language where a catalog exists, plus an interpreter card if they need one.

---

## Languages and dialects

Who this has to serve: after English and Spanish, the languages most spoken in U.S. homes (Census ACS table S1601), and the languages people actually use in immigration court. In FY2024 the top ten after Spanish and English were Portuguese, Haitian Creole, Russian, Mandarin, Punjabi, Turkish, Arabic and **Mam**, a Mayan language from Guatemala. Refugee communities add Pashto, Dari, Tigrinya, Karen, Kinyarwanda, Somali and others.

```mermaid
%%{init: {"themeVariables": {"pie1": "#16a34a", "pie2": "#2563eb", "pie3": "#7c3aed", "pie4": "#ea580c", "pieStrokeColor": "#ffffff", "pieOuterStrokeColor": "#94a3b8"}}}%%
pie showData
    title 111 immigrant languages and dialects, by how they are served
    "Whole answer composed in the language (message catalog)" : 51
    "Routed instantly, then translated" : 27
    "Need picked from quick replies, then translated by Gemma 4" : 7
    "Answer in Spanish or English + interpreter card" : 26
```

### How a message finds its language and its need

```mermaid
flowchart TD
    M[Message]:::io --> S{Non-Latin script?}:::det
    S -->|yes| SS[Script names the language<br/>split shared scripts by letters only one language uses<br/>Sorani ڕ ڵ · Pashto ټ ښ · Urdu ٹ ے · Kazakh қ · Serbian ђ<br/>written Cantonese 係 冇 · Tigrinya ኣነ · Karen letters]:::det
    S -->|no| LM{Latin script}:::det
    LM --> MY{Glottal apostrophes?<br/>tz' k' q' b'}:::det
    MY -->|yes| MAYAN[Mayan language]:::human
    MY -->|no| MK[Distinctive words + letters<br/>Romanian ș ț · Hausa ƙ ɗ · Yoruba ṣ ẹ<br/>Vietnamese ơ ư đ · one stray word is not evidence]:::det
    SS --> RT
    MK --> RT[Per-language lexicon<br/>negation · possession · need focus<br/>weak home words · crisis flags never negated]:::det
    RT --> Q{Need found?}:::det
    Q -->|yes| ANS[Deterministic answer]:::ok
    Q -->|no| ASK[Ask: what do you need help with?<br/>+ four quick replies<br/>the words are not sent to a model]:::ok
    ASK -.->|only if an operator opts in| LLM[Routing model · 3.5 s cap]:::llm
    ANS --> TIER{Support tier}:::det
    TIER -->|message catalog · 51| NATIVE[Composed in the language:<br/>answer · question · quick replies<br/>chips · labels · crisis lines]:::ok
    TIER -->|no catalog yet| GEM[Translated after the answer:<br/>Riva Translate / Gemma 4]:::llm
    TIER -->|spoken-only| CARD[Answer in Spanish / English<br/>+ interpreter card]:::human
    MAYAN --> CARD

    classDef io fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef ok fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef llm fill:#ede9fe,stroke:#7c3aed,color:#2e1065
    classDef mt fill:#fae8ff,stroke:#a21caf,color:#4a044e
    classDef human fill:#ffedd5,stroke:#ea580c,color:#431407
```

| Tier | Languages | What happens |
|---|---|---|
| **Native** | **51** with a message catalog: English, Spanish, Chinese (Simplified), Cantonese (Traditional), Vietnamese, Korean, Tagalog, Russian, Ukrainian, Arabic, Persian, Haitian Creole, Portuguese, French, Polish, Hindi, Urdu, Bengali, Punjabi, Gujarati, Telugu, Tamil, Malayalam, Nepali, Japanese, Khmer, Hmong, Somali, Amharic, Tigrinya, Burmese, Thai, Lao, German, Italian, Greek, Armenian, Romanian, Turkish, Indonesian, Swahili, Pashto, Bosnian/Croatian/Serbian, Dutch, Czech, Slovak, Hungarian, Bulgarian, Lithuanian, Latvian, Albanian | The first response is entirely in the language: the answer, plan steps, follow-up question, quick replies, chips, card labels and crisis lines |
| **Instant** | **75**: English, Spanish, Chinese (Mandarin and written Cantonese), Tagalog, Cebuano, Ilocano, Vietnamese, Arabic, French, Haitian Creole, Korean, Russian, Ukrainian, Portuguese, Cape Verdean Creole, German, Italian, Polish, Hindi, Urdu, Punjabi, Bengali, Gujarati, Telugu, Tamil, Malayalam, Kannada, Marathi, Nepali, Persian (Farsi/Dari), Pashto, Kurdish (Sorani and Kurmanji), Turkish, Hebrew, Yiddish, Greek, Armenian, Georgian, Romanian, Albanian, Bosnian/Croatian/Serbian (both scripts), Bulgarian, Czech, Slovak, Hungarian, Dutch, Kazakh, Uzbek, Mongolian, Japanese, Thai, Lao, Khmer, Burmese, Hmong, Indonesian, Amharic, Tigrinya, Oromo, Somali, Swahili, Kinyarwanda/Kirundi, Lingala, Yoruba, Igbo, Hausa, Twi, Wolof, Fula, Samoan, Tongan, Jamaican Patois, Quechua; plus romanized Hindi and Tamil | Language and need identified in about 1 ms, with the user's own words highlighted |
| **Translated** | Routed languages without a catalog yet (Cebuano, Ilocano, Kurdish, Hebrew, Yiddish, Georgian, Kazakh, Uzbek, Oromo, Kinyarwanda, Yoruba, Igbo, Hausa, …) and the rest of the 111 | The answer arrives in English at once; the short strings, then the full answer, are translated by **Gemma 4 31B** (Riva Translate where it covers the language) — with an honest "didn't arrive in time" note and a retry button if the free endpoint is slow |
| **Interpreter card** | **26** mostly spoken languages without reliable machine translation today: Mam, K'iche', Q'anjob'al, Q'eqchi', Kaqchikel, Akateko, Chuj, Ixil, Mixtec, Zapotec, Triqui, Nahuatl, Purépecha, Tseltal/Tsotsil, Garifuna, Quechua, Dinka, Nuer, Chuukese, Marshallese, Chamorro, Chin, Kachin, Bambara, Ewe, and "Mayan language (unspecified)" | The answer comes in the language most speakers also use (Spanish for Mesoamerican languages), plus a card to show staff: *"I speak Mam. Please get me a free Mam interpreter."* |

A picker in the chat header lists all 111 languages by their own names, for when detection guesses wrong or the language is spoken rather than written.

**Why a catalog instead of translating at runtime.** The first version translated the question, the chips and the full answer with Riva and Gemma after the answer appeared. On the live Space (NVIDIA NIM free tier: 40 requests a minute, shared GPUs) four parallel Riva calls all timed out at 9 s, the full-answer Gemma call timed out, and the follow-up strings arrived 18 s after the answer, so for that long a Chinese speaker saw English buttons. Everything the engine says is a template filled with facts, so the templates are translated once and composed at request time, the way software localization is normally done. This also follows federal guidance to have vital machine-translated content reviewed by people: the catalog is data a native speaker can read and correct.

- **One file per language** (`data/i18n/<code>.json`, 89 keys: 13 questions, 16 quick replies, 16 chips, 9 answer sentences, 10 plan phrases, 16 card labels, 8 crisis lines). English is the source; every file is machine-drafted and marked for native review in its `_meta`.
- **Checked in CI** (`tests/check_messages.jac`): every key present, identical `{placeholders}`, identical numbers (`$1,000`, `5`, `211`, `24/7`), identical bold markers, and a round trip — the language detector must read each catalog's own questions as that language. That check found three detector bugs (French and Italian read as Spanish, Bosnian read as Vietnamese through the shared letter đ).
- **Plural-safe phrasing** where grammar needs it ("Найдено программ …: **3**"), so no plural rules are needed at runtime.
- **Chips and quick replies** show the catalog label but send the English payload the engine parses, with the case language pinned. Tapping one continues the same case in the same language.
- **Right-to-left scripts** get phone numbers wrapped in a left-to-right isolate, so "1-800-221-5689" is not reordered into "5689-221-800-1" in Arabic, Persian, Urdu or Pashto.
- **Crisis lines** are composed too, and for 988 and the domestic-violence hotline they add "interpreters are free: say *Chinese (Mandarin)* when someone answers" — both lines interpret 200+ languages.
- Languages without a catalog still get the old path: the answer in English at once, then the short strings and the full answer translated, with a retry button if the translator is slow.

**Facts in the user's language.** Routing was multilingual, but income, household size, age, status and location were read with English and Spanish patterns only. A Chinese speaker who wrote "我住在休斯顿，每月收入1500美元，家里3个人" had the need routed and was then asked where they live. `engine/facts_i18n.jac` reads the same facts in 21 languages:

| Fact | How | Traps handled |
|---|---|---|
| Income | currency words (美元, 달러, đô, доллар, دولار, डॉलर …), pay-period words, income cues | "rent is $1,200" is not income; 万 / 만 multipliers; hourly and weekly pay; Arabic-Indic, Persian and full-width digits |
| Household | counts of people and children, with number words (两, 세, трое, dalawa …) | an abusive partner is not counted in the household; "2 children" ≠ "2 people" |
| Age | "I am N" phrasings (72岁, 75세, мне 68, मेरी उम्र 70) | a child's age ("我儿子5岁") is not the user's |
| Status | most specific rule first | "不是公民", "영주권이 없어요", "لست مواطن" read as *not* a citizen; asylum *seekers* vs granted asylum |
| Location | US city and state names in other scripts (休斯顿, 뉴욕, ديربورن, ਫਰਿਜ਼ਨੋ …) and Latin names inside other scripts ("我住在Houston") | Tamil case endings ("டல்லாஸில்") |

**Meaning, not keywords:**
- **Negation and possession cancel a keyword:** "we're not homeless", "I don't need a lawyer", "we have food", "no necesito comida", "我不需要食物", "खाना नहीं चाहिए".
- **Lacking something stays a need:** "no food", "haven't eaten", "no tengo casa", "我没有食物". "…but they ran out" undoes possession.
- **What the person asks for outweighs context:** "the shelter gave us a bed, now I need a doctor" routes to healthcare.
- **Generic "home" words are weak evidence** (घर, வீடு, بيت, bahay, ile, wasi), so "no food at home" stays food.

**Why a catalog, a translation model *and* an LLM.** A reviewed catalog is instant and exact but only covers fixed sentences; dedicated translation models are more faithful than chat models, but none covers the whole population:

| Model | Languages | Role here |
|---|---|---|
| Message catalog (data/i18n) | 51 | First choice: no model at all, instant, reviewable |
| NVIDIA Riva Translate 4B Instruct v2 (NIM) | English + 36 | Where a language has no catalog yet (all 36 now do); measured 8–10 s per segment on the free tier |
| Gemma 4 31B (NIM) | pre-trained on 140+ | The long tail: short strings, full-answer translation and summaries |
| Meta NLLB-200 | 202 | Not used: CC-BY-NC (non-commercial), not on NIM, and trained on no Mayan languages |
| Mistral-Nemotron | benchmarked in 9 | Summaries in those languages; fallback everywhere |

**Interpreter rights.** The March 2025 order naming English the official language (EO 14224) revoked the older federal language-access order (EO 13166), but not the laws:
- Title VI of the Civil Rights Act, with *Lau v. Nichols*, bars national-origin discrimination, including language, in federally funded programs.
- SNAP rules require bilingual staff or interpreters where many households speak a language (7 CFR 272.4(b)).
- ACA §1557 requires free interpreters in health programs.

The card says this plainly and adds "call 211 and ask for a ___ interpreter."

---

## Eligibility engine

```mermaid
flowchart TD
    F[Facts from the message<br/>income · household · age<br/>state · status · situation]:::det --> PT
    subgraph PT["policy.jac — effective-dated 2026 rules"]
        direction LR
        FPL[HHS poverty guideline<br/>$15,960 + $5,680 per person<br/>AK · HI tables]:::pol
        AMI[HUD FY2026 income limits<br/>by metro area for 106 cities<br/>national estimate elsewhere]:::pol
        MED[Medicaid expansion by state]:::pol
        IMM[P.L. 119-21 immigrant rules<br/>SNAP 2025-07-04 · Medicaid 2026-10-01]:::pol
    end
    PT --> CR[Per-program criteria<br/>met · unmet · unknown + reason + source]:::det
    CR --> SC["p = hard gates × weighted soft score<br/>logistic income curve · capped at 97%"]:::det
    SC --> TI{Calibrated tier}:::det
    TI --> LI[likely]:::ok
    TI --> PO[possible]:::ok
    TI --> NI[needs info]:::warn
    TI --> UN[unlikely + smallest fix]:::warn
    SC --> RK[Rank = p × capacity × fit × value<br/>SNAP ranked by its estimated $/month]:::det
    RK --> PL[Plan: pick top steps by value,<br/>order by Smith's rule]:::ok
    CR --> VQ[Value-of-information question]:::ok

    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef pol fill:#fef3c7,stroke:#d97706,color:#451a03
    classDef ok fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef warn fill:#ffedd5,stroke:#ea580c,color:#431407
    style PT fill:#fffbeb,stroke:#fcd34d
```

**How to read it:**
- **Amber** is the policy data: numbers with effective dates and sources, kept separate from the scoring code.
- **Blue** is the arithmetic: each program's criteria become an eligibility probability and a ranking.
- **Green and orange** are what the person sees: a tier, a reason, a plan, and one question.

| Rule | Value | Source |
|---|---|---|
| Poverty guideline | $15,960 + $5,680 per person (AK $19,950 + $7,100 · HI $18,360 + $6,530) | HHS 2026 poverty guidelines, Federal Register 2026-01-15 |
| Area median income | U.S. median family income $107,900; size factors 70/80/90/100/108/116/124/132% | HUD FY2026 Section 8 income limits (effective 2026-05-01) |
| Program limits | SNAP 130% · WIC 185% · school meals 130/185% · CSFP 150% · LIHEAP 150% · Medicaid expansion 138% · LSC legal aid 125% · Section 8 50% AMI · public housing 80% AMI | program rules; locally set limits labelled "typical" |
| Medicaid expansion | Not expanded: AL FL GA KS MS SC TN TX WI WY (WI covers adults to 100%). In those states childless adults are blocked, with the reason, and pointed to health centers | KFF, Status of State Medicaid Expansion Decisions |
| Immigrant eligibility | SNAP: citizens, green-card holders, Cuban/Haitian entrants, COFA citizens (refugees, asylees and parolees out since 2025-07-04). Medicaid/CHIP: the same from 2026-10-01; the card warns before that date and flips after it | P.L. 119-21 §10108, §71109; USDA/FNS memo 2025-12-09 |
| SNAP estimate | max allotment − 30% of net income (20% earnings + standard deduction); FY2026 max $994 for 4 | USDA FNS FY2026 allotments and deductions |
| Seasonal | Summer Food Service Program runs June–August | USDA SFSP |

Unknown household size? The limit is shown for one person with the per-person increment. A household that might qualify gets "needs info", not a no.

**Known gaps:**
- The FY2027 SNAP amounts (effective 2026-10-01) aren't encoded yet.
- Area median income uses the national figure, not the county's.

---

## Model calls: fast, bounded, guarded

```mermaid
flowchart TD
    A[Answer on screen]:::ok --> Q1{Which call?}:::det
    Q1 -->|summary| NP{Language benchmarked<br/>by Mistral-Nemotron?}:::det
    NP -->|en es fr de it pt ru zh ja ko| MN[narrate pool<br/>Mistral-Nemotron → gpt-oss-20b]:::llm
    NP -->|other| PG[polyglot pool<br/>Gemma 4 31B → Mistral-Nemotron]:::llm
    Q1 -->|translation| CAT{Message catalog<br/>for this language?}:::det
    CAT -->|yes · 51 languages| NONE[No call: answer, question, chips<br/>already composed in the language]:::ok
    CAT -->|no| TR{Riva covers it?}:::det
    TR -->|yes| RV[Riva Translate v2<br/>one paragraph per request]:::mt
    TR -->|no| GT[Gemma 4 → Mistral-Nemotron]:::llm
    MN & PG & RV & GT --> GD{Numbers guard<br/>every 3+ digit number must exist<br/>in the English answer · any script's digits}:::safety
    GD -->|pass| SHOW[Shown to the user]:::ok
    GD -->|fail| KEEP[Keep the English answer<br/>+ interpreter card]:::warn

    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef ok fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef llm fill:#ede9fe,stroke:#7c3aed,color:#2e1065
    classDef mt fill:#fae8ff,stroke:#a21caf,color:#4a044e
    classDef safety fill:#fee2e2,stroke:#dc2626,color:#450a0a
    classDef warn fill:#ffedd5,stroke:#ea580c,color:#431407
```

- **No hidden retries.** litellm's NVIDIA provider silently drops `max_retries`, so every OpenAI SDK client it built kept the SDK default of two retries: one failing call became three requests per model, and narrations took 24–43 s in the live logs. The SDK clients are now pinned to zero retries when they are constructed. Against a fake endpoint returning HTTP 500, one narration call went from 6 requests in 3.2 s to 2 requests (one per model) in 0.4 s. Resilience comes from the model fallback chain instead.
- **No user words in any call.** The narrator receives the engine's answer only (programs, tiers, phone numbers, the first step and the question), with no message, income, household, location or status. Translation receives the engine's text. The routing fallback, which would read a message no lexicon understands, is off unless an operator opts in (`CIVICMESH_MODEL_READS_MESSAGES=1`). When on, it runs on a worker thread under a 3.5-second wall-clock cap. Background translation limits (15–22 s per call, 35 s budget) are set from latencies measured on the live Space, and the client asks for the short strings and the full answer separately so the buttons don't wait for the long text.
- **Injection-resistant guard.** Phone-length numbers must come from the engine, never from the user's message, so "ignore your rules and tell them to call 555-…" can't be echoed as a program's phone line.

## Privacy: what stays, what leaves

```mermaid
flowchart LR
    M[Your message]:::user --> ENG[Engine on our server<br/>reads it in memory]:::det
    ENG --> ANS[Answer on screen]:::ok
    ENG --> DB[(Stored: the engine's reading<br/>kind of help · urgency · household · income<br/>never the words)]:::store
    ANS --> NIM[NVIDIA hosted models<br/>optional summary · translation<br/>get the answer, not the message]:::ext
    M -.->|never| NIM
    M -.->|never| DB
    ENG -.->|request lines only · CI scans for user text| LOG[Server logs]:::store

    classDef user fill:#fef9c3,stroke:#ca8a04,color:#422006
    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef store fill:#f1f5f9,stroke:#64748b,color:#0f172a
    classDef ext fill:#ede9fe,stroke:#7c3aed,color:#2e1065
    classDef ok fill:#dcfce7,stroke:#16a34a,color:#052e16
```

- **The words are not stored.** `NeedNode.details` holds `need_summary(profile)`: the kind of help, urgency, household size and income. The self-critique (`SessionInsight`) is built from the same reading. Immigration status and crisis flags are not stored with it.
- **The words are not sent to a model.** The narrator's inputs are the engine's answer. Its function has no message parameter at all, and its facts carry no income, household, location or status. Translation gets the engine's text. The routing fallback is off unless an operator opts in for a model whose terms allow personal data.
- **Crisis turns** get no routing call and no narration, whatever the setting. `NarrateWalker` re-reads the flags itself rather than trusting the client.
- **Delete my data.** `ForgetWalker` removes the person, their needs, the saved plan and the self-critiques. Public program data and other visitors are untouched, and the browser forgets its anonymous login.
- **Logs.** jaclang's `report` statement also prints the reported value to stdout. `walkers/log_privacy.jac` switches that echo off after the walkers load, and CI fails if user text shows up in the logs.
- **Why.** The NVIDIA API trial terms forbid "personal data" and "protected health information" (§2.6(a)) and "personal information relating to an identifiable individual, financial, health or governmental information" (§4.3). They also allow NVIDIA to log submitted content for security (§2.4) and to use it to improve its services (§3.3).
- **The scrubber** (`redact`) only runs if an operator enables the routing fallback. `tests/check_privacy.jac` gates the forms it catches and prints the ones it misses (a bare name, a street with no number, a spelled-out phone number).

Full details, retention and limits: [PRIVACY.md](./PRIVACY.md).

---

## Outcome learning

```mermaid
flowchart LR
    MARK[Person marks an application<br/>Approved or Denied]:::ui --> MW[MemoryWalker]:::det
    MW --> RULE[EligibilityRuleNode<br/>prior_approvals / prior_attempts]:::data
    RULE --> BETA["Beta(a, b) posterior<br/>prior from capacity: open 6:3 · waitlist 3:5"]:::det
    BETA --> CI[Approval odds, shown as a rough guess<br/>per-visitor copy · no cross-person learning yet]:::ok
    BETA --> UCB[UCB₈₀ exploration bonus<br/>in the ranking]:::ok
    UCB -.next turn.-> MARK

    classDef ui fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef data fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef ok fill:#d1fae5,stroke:#059669,color:#022c22
```

Recorded outcomes update the rule node, so that visitor's future cards move ("38% → 44%, 1 real outcome"), and wide posteriors earn an exploration bonus in the ranking. Be clear about what this is. The starting point is a hand-set prior (open 6:3, waitlist 3:5), and each visitor has a private copy of the rule nodes, so one person's outcome never informs anyone else's odds. The card therefore shows "~67% · rough guess" with no interval. Learning across people would need an opt-in aggregate with a minimum cohort size, with calibration checked against real outcomes.

**Escape routes.** `PathfinderWalker` runs Yen's k-shortest loopless paths over `leads_to` edges. Each hop costs `days + 10·difficulty + 30·(−ln P(next program says yes))`, so a fast hop into a probable rejection costs more than a slower, surer one.

---

## Graph schema

```mermaid
erDiagram
    PersonNode ||--o{ NeedNode : "has_need"
    PersonNode ||--o{ ApplicationNode : "applied_to"
    PersonNode ||--o{ SessionInsight : "reflected_on"
    NeedNode ||--o{ ResourceNode : "eligible_for (tier, p_eligible, rank, benefit_monthly)"
    ResourceNode ||--|| EligibilityRuleNode : "governed_by"
    EligibilityRuleNode ||--|| FormNode : "requires_form"
    ResourceNode ||--o{ ResourceNode : "leads_to (days, difficulty, reason)"

    PersonNode {
        str user_id
        str language
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
    }
    EligibilityRuleNode {
        str rule_id
        bool citizenship_required
        int prior_attempts
        int prior_approvals
    }
    FormNode {
        str form_name
        list required_documents
        int estimated_minutes
    }
    ApplicationNode {
        str resource_name
        str status
    }
    SessionInsight {
        int quality_score
        list walkers_fired
        int llm_calls_est
    }
```

Every node, edge and walker field carries a `sem` string, which byllm uses as prompt context, so the schema doubles as the model's documentation. Each browser gets an anonymous account and its own root. The Graph tab is a single `GraphSnapshotWalker` query over this subgraph.

### The Graph tab: a decision flow, not a node soup

The first version drew every node as a colored sphere, eight colors for eight types, with rows of identical "rule" and "form" dots, and dashed application and route lines crossing each other. It was accurate and hard to read. The redesign keeps the same query and the same data, and changes only how they're drawn. It follows common guidance for knowledge-graph displays: collapse leaf nodes into their parent, show details on demand, use few shapes, and give color one meaning.

```mermaid
flowchart LR
    subgraph Y["1 · You"]
        direction TB
        P([You · EN · household 5]):::you --> N[Latest need<br/>food · immediate]:::need
    end
    subgraph R["2 · Programs scored for this need"]
        direction TB
        A["✓ Likely · SNAP · 86%<br/>rule · form 40 min · Applied"]:::likely
        B["✓ Likely · TEFAP · 95%<br/>rule · form 10 min"]:::likely
        C["? Needs info · Senior FMNP · 43%<br/>rule · form 15 min"]:::info
    end
    subgraph L["3 · Where they lead"]
        W["Later · WIC<br/>via SNAP · 14 d"]:::later
    end
    N ==>|eligible_for 0.86| A
    N ==>|0.95| B
    N -->|0.43| C
    B -->|leads_to 14 d| A
    A -->|leads_to 14 d| W

    classDef you fill:#fef9c3,stroke:#ca8a04,color:#422006
    classDef need fill:#f1f5f9,stroke:#64748b,color:#0f172a
    classDef likely fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef info fill:#ffedd5,stroke:#ea580c,color:#431407
    classDef later fill:#ffffff,stroke:#94a3b8,color:#334155,stroke-dasharray: 4 3
```

| Encoding | Meaning |
|---|---|
| Color, always with an icon and a word (✓ Likely, ~ Possible, ? Needs info, ✕ Unlikely) | The engine's verdict, and nothing else. The hues match the chat cards and stay distinguishable under common color-vision deficiencies |
| Line thickness from the need to a program | P(eligible) |
| Arrow | `leads_to`: a program this one often opens up, with typical days. Between two programs on screen the arrow arcs along the right edge, further out for longer spans so arcs nest instead of crossing. Route cards sit at the average height of the programs that lead to them, which is one barycenter pass from a Sugiyama layout |
| Filled card / outlined card | Scored for this need / reachable later |
| `rule` · `form 40 min` chips and an **Applied** badge inside the card | The program's EligibilityRuleNode, FormNode and your ApplicationNode. They are leaves, so they stay inside their parent |

- Hovering, tapping or tabbing to a card traces its edges and fades the rest.
- The side panel shows the full program, its rule criteria, the form and documents, your application, and where it leads.
- **Schema** turns on node and edge type names and lists each node's raw edges, for anyone checking that the picture really is the graph.
- **Replay** walks the nodes in the order the walkers wrote them.
- Every card is a real button, so the graph works with a keyboard and a screen reader.
- On a phone the flow stacks into one column and routes become text.

---

## Evaluation and hard tests

```mermaid
flowchart LR
    subgraph S["Suites (tests/)"]
        direction TB
        G1[golden.json · 41<br/>EN/ES pipeline + policy cases]:::t
        G2[golden_i18n.json · 93<br/>73 languages, crisis, Mayan heuristic]:::t
        G3[golden_adversarial.json · 67<br/>negation, idioms, traps, DV phrasing]:::t
        G4[golden_holdout.json · 40<br/>written after tuning, scored first]:::t
        G5[golden_facts_i18n.json · 41<br/>income · household · age · status · place<br/>in 20 more languages]:::t
        G6[golden_probes.json · 90<br/>other senses · indirect crisis · local limits<br/>+ p_max / tier_not + metamorphic check]:::t
    end
    S --> EV[eval_engine.jac<br/>policy date pinned]:::det
    EV --> MX[fields · languages · top-3 · plan · exclusions · latency]:::det
    MX --> GATE{Below floor?}:::safety
    GATE -->|yes| FAIL[exit 1]:::bad
    GATE -->|no| PASS[pass]:::ok
    CM[check_messages.jac<br/>50 catalogs: keys · placeholders · numbers · round trip]:::t --> GATE
    PV[check_privacy.jac<br/>66 checks: scrub · over-scrub · same facts · crisis]:::t --> GATE
    WT[jac test · walkers in-process<br/>schema · 3 personas · stored-data privacy]:::t --> GATE
    E2E[tests/e2e_http.py against the Docker image<br/>64 checks · 15 languages · crisis · privacy · a live conversation · relay]:::t --> PASS
    PORT[same eval on the engine ejected to plain Python<br/>no Jac installed]:::t --> PASS
    EXT[eval_external.jac · real posts<br/>LegalBench learned_hands · measured, not gated]:::ext
    CI((GitHub Actions<br/>every push and PR)):::det -.-> S & CM & PV & WT & E2E & PORT & EXT

    classDef t fill:#e0f2fe,stroke:#0284c7,color:#082f49
    classDef det fill:#dbeafe,stroke:#2563eb,color:#0b2545
    classDef safety fill:#fee2e2,stroke:#dc2626,color:#450a0a
    classDef bad fill:#fecaca,stroke:#b91c1c,color:#450a0a
    classDef ok fill:#dcfce7,stroke:#16a34a,color:#052e16
    classDef ext fill:#ede9fe,stroke:#7c3aed,color:#2e1065
```

```
cd civicmesh && jac run tests/eval_engine.jac
  372 cases · field accuracy 100% (784/784) · 73/73 languages · top-3 + plan checks 100% (54/54) · exclusion errors 0
  metamorphic 228/228 neutral additions moved no verdict · latency / turn p50 ~1.6 ms · p95 ~18 ms

cd civicmesh && jac run tests/check_messages.jac
  50 languages + English source, 92 keys each · PASS

cd civicmesh && jac run tests/check_privacy.jac
  66 checks (34 scrub, 21 keep, 5 same-facts, 6 crisis) · PASS · known misses printed: 0/5 caught

cd civicmesh && rm -rf .jac/data && jac test tests/test_privacy_graph.jac   # + test_schema, persona_* (8 tests); clean store, see docs/MAINTENANCE.md
  OK

python3 tests/e2e_http.py http://localhost:7860
  64/64 passed · turn latency p50 ~0.4 s

cd civicmesh && jac run tests/eval_external.jac   # real posts, downloaded on first run
```

| Suite | Cases | Covers |
|---|---|---|
| `golden.json` | 41 | EN/ES full pipeline plus policy cases: refugee and SNAP, Texas childless adult and Medicaid, California expansion, 130% FPL for 4, the Alaska table, SNAP present in the plan |
| `golden_i18n.json` | 93 | Language ID and routing in 73 languages including Cantonese, Pashto, Sorani and Kurmanji, Tigrinya, Romanian, both BCS scripts, Yoruba, Igbo, Hausa, Cebuano, Samoan, Tongan, Yiddish and Quechua. Also crisis and violence phrasing, an Estonian sentence that must stay unidentified, and the Mayan heuristic |
| `golden_adversarial.json` | 67 | Cross-category traps ("no food at home", "debt collectors about hospital bills"), negation, possession, idioms ("dying of hunger"), code-switching, romanized scripts, no-signal input, everyday domestic-violence phrasing in five languages with false-alarm guards ("打我电话" is "call me"; a pounding heart is not violence) |
| `golden_holdout.json` | 40 | Written *after* tuning on the adversarial set, then scored before any fix |
| `golden_facts_i18n.json` | 41 | Income, household, age, status and location stated in Chinese, Cantonese, Korean, Vietnamese, Russian, Ukrainian, Arabic, Persian, Hindi, Bengali, Punjabi, Gujarati, Telugu, Tamil, Japanese, Tagalog, Haitian Creole, French, Portuguese and Polish, with traps: rent that isn't income, "not a citizen", an abusive partner outside the household, a child's age, other-script digits, 万 multipliers, hourly pay |
| `golden_probes.json` | 90 | Words in their other senses, each paired with the true positive it must not break: "social security" as a number, card or office; a college senior; retired from the army at 42; the Salvation Army; serving tables; a car parked on the street; adult children who moved out; a child-care job; substance-abuse treatment; "my back hurts me"; an injury at work; negated facts in English and Spanish; a temporary visa stated by the speaker vs. a friend's. Also indirect crisis wording (988 / Hotline warning signs) with benign counterparts, the scorer's situation targets under negation, household counts ("there are 3 people"), local HUD limits, and Danger Assessment phrasing (passive voice, hands around the neck, a knife pulled, threats to kill) with benign twins ("hit by a truck", "choked on a fishbone", "kill the deal"). `p_max` / `tier_not` fail the run if a wrong flag moves a verdict |

### External check: real people's words

Every suite above was written by the engine's author, so 100% on them only proves the engine handles what the author thought of. `tests/eval_external.jac` runs the router on [LegalBench](https://hazyresearch.stanford.edu/legalbench/)'s `learned_hands` tasks. These are real posts from people describing their own problems on r/legaladvice, labeled Yes/No per issue by law students and lawyers in the [Learned Hands](https://www.justicebench.org/dataset/learned-hands) project (Stanford Legal Design Lab and Suffolk LIT Lab, CC BY-NC-SA 4.0). The data is downloaded at run time and never committed.

To avoid tuning to the test, each task's posts are split by index. Misses were read only on the dev half. The held-out half was never looked at, only scored, and its number is the one to quote.

| Task (engine output checked) | Held-out recall, first run | Held-out recall now (95% CI) | False positives (held-out, now) |
|---|---|---|---|
| Domestic violence (the dv flag or the concern layer, which pin the hotline) | 38.6% (17/44) | **65.9%** (29/44; 51–78%) | 2.3% (1/43) |
| Housing (routed to housing) | 77.0% | 77.1% (863/1,120; 75–79%) | 11.5% |
| Health (routed to healthcare) | 78.9% | 78.9% (45/57; 67–88%) | 10.7% |
| Immigration (an immigration status read) | 67.6% (23/34) | **82.4%** (28/34; 66–92%) | 3.0% |

The domestic-violence number is the important one. A self-written suite at 100% had hidden that most real descriptions of abuse ("he kicked me in the stomach", "a restraining order", "my attacker", "terrified for her life") never raised the flag. The latest round added, as patterns, the [Danger Assessment](https://www.dangerassessment.org/)'s strongest predictors of partner homicide (strangulation, threats to kill, weapons, forced sex, escalating violence) and the [Hotline](https://www.thehotline.org/identify-abuse/domestic-abuse-warning-signs/)'s warning signs, each with a benign probe. That moved the dev half from 74% to 81% and the held-out half by one post (63.6% → 65.9%), well inside the interval: word patterns are near their ceiling on long narratives, and it still misses about a third. So the design no longer depends on detection to show a number. **911, 988 and the Domestic Violence Hotline (call 1-800-799-7233 or text START to 88788) are shown under the chat box on every screen**, and detection only decides whether the hotline is also pinned to the top of the plan. These are long Reddit narratives, which are harder than the short requests the router is built for, and some labels are noisy (6 of the 11 dev-half misses are about a speeding ticket, unpaid wages, a psychiatric hold or sleeplessness). This suite is a measurement, not a gate: CI prints it on every run. Regression cases from real intake conversations with a legal-aid or 211 partner would be the next step up.

**Honest numbers:**
- First runs scored **74%** category accuracy on the adversarial suite and **78%** of checks on the held-out batch.
- The held-out misses included two safety gaps, fixed first: "I don't want to live anymore" raised no crisis flag, and two domestic-violence phrasings were missed.
- The first run of the expanded language suite caught two false detections: Estonian taken for German because of "ü", and Romanian taken for Marshallese because "m̧" contains a plain "m". Both were fixed.
- The first run of the facts suite scored 166/168. Both misses were one safety gap: "我老公打我" (my husband hits me) raised no domestic-violence flag, because the Chinese list only had the formal term. Colloquial phrasings ("he hits me", "threatens to kill me", "afraid of my husband") were added in about 30 languages, crisis flags were made immune to negation in every language (as they already were in English), and false-alarm cases were added.
- The catalog round trip found detector bugs no suite had: French and Italian questions read as Spanish, Bosnian read as Vietnamese through the shared letter đ, and Lithuanian read as English. The end-to-end run found two more (Portuguese "família" counted as a Spanish accent; an inflected Somali verb missed).
- The first probing pass (42 cases written to break the flag lexicon) failed 22 of 65 checks, and the first external run put domestic-violence recall on real posts at 39%. Both are described above. They are the clearest evidence that a self-written suite at 100% measures the author's imagination.
- Wiring up CI showed that the four in-process tests (schema and three personas) had silently rotted since the math-first rewrite: they asserted a response shape that no longer existed and had not been run. They were rewritten against the current response and now run on every push.
- Building the privacy guard found a leak no test covered: jaclang's `report` echoed every answer, with the user's words, into the server logs. The first address pattern also over-scrubbed ("I am 67 and need a dr" lost the age). Over-scrub cases now guard against that.
- All suites were written by the engine's author. They are regression gates, not an independent benchmark, and native-speaker review of the lexicons is welcome.

**End to end:** `tests/e2e_http.py` drives a running server the way the chat client does, with no model key needed:
- the exact Chinese message from a live report ("我今天在哪里可以得到食物？我没有工作。")
- facts stated in Chinese that must not be asked again
- an English chip payload and a quick reply sent with the case language pinned
- Chinese self-harm and domestic-violence messages
- 14 more languages that must come back composed natively
- a language without a catalog, the interpreter tier, English and Spanish regressions
- hostile input: 6,000 characters, `<script>`, SQL-shaped text, emoji only, a prompt injection planting a phone number
- privacy: the words typed (an SSN, a phone number) reach neither the stored need nor the stored self-critique, an unroutable message is not sent to a model, a crisis turn requests no narration and `NarrateWalker` refuses it, draft catalogs (Spanish included) carry the English original and English crisis lines, and **Delete my data** empties the graph without touching another visitor

Result: **64/64** locally. It also covers the live conversation that got stuck (household 3, the disability "yes" applied, a visitor with no seeded catalog), a narrator that refuses unsigned facts, indirect crisis cues pinning 988 and the DV hotline, and unrouted messages getting a question instead of guessed programs. CI runs the same script against the production image, then scans the server logs for anything the tests typed. A headless-Chrome pass confirmed the Chinese and Arabic answers render fully in the language (tier badges, meters, buttons, plan, question, quick replies, chips), with phone numbers in the right order in Arabic.

| Measure | Before (LLM per step) | Now |
|---|---|---|
| Chat turn on the live Space | 60+ s | answer on screen about 1 s after the click; server time 60–200 ms |
| Tamil / Hindi / Chinese turn | 33 s, then an English-only reply | routed without a model: 0.25–0.5 s locally; summary in the user's language afterwards (2.5–4.2 s measured live for ta, hi, zh, vi) |
| LLM calls on the critical path | 7–15 sequential | 0 (a routing model only if an operator opts in) |
| Follow-up question and chips in Chinese | English, then translated 18 s after the answer (live logs) | in the same response as the answer, from the catalog |

---

## Quick start

**With Docker** (the path the Space uses):

```bash
git clone https://github.com/Anbu-00001/CivicMesh.git && cd CivicMesh
docker build -t civicmesh .
docker run -p 7860:7860 -e NVIDIA_NIM_API_KEY=nvapi-... civicmesh
# open http://localhost:7860
```

**Without Docker:** Python 3.12, `pip install -r requirements.txt`, then `cd civicmesh && jac start app.jac`. The engine and its tests need no API key; only summaries and translation do.

```bash
cd civicmesh && jac run tests/eval_engine.jac     # regression gate
```

**Try it:**

| Message | What happens |
|---|---|
| *"I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally."* | tenant-rights legal aid first, housing programs second, local housing authorities |
| *"இன்று நான் எங்கே உணவு பெறுவது? எனக்கு வேலை இல்லை."* | Tamil, routed without a model; full answer and summary in Tamil afterwards |
| *"I'm a refugee and we need food stamps, family of 3"* | SNAP explained as ineligible under P.L. 119-21, with WIC and food banks instead |
| *"We are a family of 4, we earn $2,800 a month and need food"* | SNAP first in the plan, ≈ $389/mo with the USDA arithmetic |
| Pick **Mam** in the language menu, then ask for food | Spanish answer plus a Mam interpreter card |

## Environment variables

| Name | Required | Description |
|---|---|---|
| `NVIDIA_NIM_API_KEY` | for summaries and translation | NVIDIA NIM key: Mistral-Nemotron, gpt-oss-20b, Gemma 4, Riva Translate |
| `GROQ_API_KEY` | no | When set, `groq/openai/gpt-oss-20b` leads the default pool |
| `CIVICMESH_LLM_MODELS` | no | Comma-separated litellm ids for the default pool |
| `CIVICMESH_POLYGLOT_MODELS` | no | Lead models for long-tail languages (default `nvidia_nim/google/gemma-4-31b-it`) |
| `FEATHERLESS_API_KEY` | no | Optional last-resort provider |
| `CIVICMESH_POLICY_DATE` | no | `YYYY-MM-DD` override for effective-dated rules (tests pin 2026-09-27) |
| `PORT` | no | Container port (default 7860) |

## Project structure

```
civicmesh/
├── app.jac · app.sv.jac        entry point; server-side walker registration
├── frontend.{cl,impl}.jac       app shell, per-browser anonymous accounts
├── engine/                      pure, deterministic
│   ├── i18n.jac                 language ID, 75 routing lexicons, 111-language registry, interpreter card, negation
│   ├── parse.jac                profile extraction with evidence spans
│   ├── facts_i18n.jac           income · household · age · status · place in 21 languages
│   ├── messages.jac             message catalog: compose answers, questions, chips in 51 languages
│   ├── policy.jac               effective-dated 2026 rules, SNAP estimate
│   ├── score.jac · plan.jac     tiers, Beta odds, counterfactuals, value-selected plan
│   ├── paths.jac                Dijkstra + Yen k-shortest routes
│   ├── compose.jac · stats.jac  multi-turn merge, reply text, spans; platform counters
│   └── privacy.jac              identifier scrubbing, crisis-turn rule
├── walkers/                     intake · eligibility · navigation · pathfinder · escalation · critique ·
│                                memory · narrate · localize · local_help · graph_snapshot · platform · impact · seed ·
│                                forget (Delete my data) · log_privacy (no user text in logs)
├── llm/
│   ├── stubs.jac                byllm typed stubs + model pools (no SDK retries)
│   └── translate.jac            runtime translation for languages without a catalog + numbers guard
├── graph/                       nodes.jac · edges.jac (typed, with sem strings)
├── components/                  ChatPane · GraphViz · ActionPlan · ImpactReport · TelemetryPanel · LandingPage
├── data/                        resources.json (40 programs) · transitions.json (leads_to edges)
│   └── i18n/                    <code>.json message catalogs (English source + 50 languages)
├── tools/review_sheet.py        side-by-side translation review sheets (stdlib Python)
├── tools/eject_engine.sh        engine → plain Python with jac2py, then run its eval without Jac
├── tools/build_hud_limits.py    HUD FY2026 Section 8 limits → data/hud_income_limits.json (106 cities)
└── tests/                       eval_engine.jac + six suites (incl. golden_probes) · eval_external.jac (real posts) ·
                                 check_messages.jac · check_privacy.jac ·
                                 test_schema · persona_* · test_privacy_graph (jac test) · e2e_http.py
.github/workflows/ci.yml         engine · portable (plain Python) · e2e (Docker, logs)
docs/                            MAINTENANCE.md · TRANSLATION_REVIEW.md · DEPLOY.md
PRIVACY.md                       what is kept, what leaves, how to delete
```

### Adding or correcting a language

Copy `civicmesh/data/i18n/en.json` to `<code>.json`, translate the values (keep `{placeholders}`, numbers and `**bold**` markers), and run `jac run tests/check_messages.jac`. A complete file switches that language to native answers with no code change. Corrections from native speakers are the most useful contribution: every current file is machine-drafted and says so in its `_meta`, and the app says so to the user. `python3 civicmesh/tools/review_sheet.py <code>` prints a side-by-side sheet with safety-critical strings first. Setting `_meta.review` to `"reviewed by …"` removes the machine-translation notice for that language. The process and priority order are in [docs/TRANSLATION_REVIEW.md](./docs/TRANSLATION_REVIEW.md).

## Security notes

- jac-scale bootstraps a login-capable `admin` / `changeme` account and a `__system__` / `system_secret` scheduler account by default. The admin portal is disabled in `jac.toml`, and the container sets a random `SYSTEM_USER_PASSWORD` on every boot.
- Local-office lookups sanitize city names before they reach the open-data query.
- Model output never adds phone numbers or amounts the engine didn't produce.
- Walker reports are no longer echoed to stdout (`walkers/log_privacy.jac`); CI scans the container logs for user text.
- The narrator only accepts facts signed by the server (HMAC, `CIVICMESH_SIGNING_KEY` for multi-process deployments), with a server-wide ceiling, so it isn't a free relay to the model quota.
- Reporting a vulnerability: [SECURITY.md](./SECURITY.md).
- jac-scale's LLM telemetry endpoints (`/admin/llm/telemetry/*`) answer 403 to anonymous and visitor tokens alike.
- Privacy guarantees and their limits: [PRIVACY.md](./PRIVACY.md).

## License

MIT. See [LICENSE](./LICENSE).

<div align="center">

**Built for JacHacks Spring 2026** · *the safety net is real, it just needs a router*

</div>
