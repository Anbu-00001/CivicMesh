"""byLLM stubs — the pipeline's entire LLM surface: at most ONE call per turn.

Everything that can be computed is computed (engine/*.jac). The model is used
only where language is genuinely open-ended:

  understand_message  sync, only when the deterministic parser can't route the
                      message (no category evidence, or a language other than
                      English/Spanish). Tight timeout, no retries.
  narrate_turn        async, OFF the critical path: the client already shows
                      the deterministic answer; this adds a warm, localized
                      two-sentence summary and translates follow-up chips.

Each stub is a typed Meaning-Typed-Programming function (`by <pool>`): the
return object + `sem` strings are the prompt, byllm enforces the schema.
"""

import os;
import openai;
import from byllm.lib { Model, ModelPool }

# ---------- no hidden SDK retries ----------
# litellm's NVIDIA NIM provider drops `max_retries` as an unsupported param,
# so every OpenAI SDK client it builds falls back to the SDK default of 2
# retries — a 5 s timeout became 3 × 5 s per model, and a failing endpoint got
# 3 requests per attempt (reproduced against a fake HTTP-500 endpoint: 6
# requests for one 2-model call). Resilience here comes from the model
# fallback chain and walker deadlines, so SDK clients are pinned to 0 retries
# at construction, for every provider, before any pool exists.

"""Wrap an SDK client __init__ so it always gets max_retries=0."""
def _zero_retries(orig: Any) -> Any {
    def init(self: Any, *args: Any, **kwargs: Any) -> None {
        kwargs["max_retries"] = 0;
        orig(self, *args, **kwargs);
    }
    init._civicmesh_zero_retries = True;
    return init;
}

"""Pin OpenAI / AsyncOpenAI (and Azure variants) to zero retries. Idempotent."""
def pin_sdk_retries -> bool {
    for name in ["OpenAI", "AsyncOpenAI", "AzureOpenAI", "AsyncAzureOpenAI"] {
        cls = getattr(openai, name, None);
        if cls is not None and not getattr(cls.__init__, "_civicmesh_zero_retries", False) {
            cls.__init__ = _zero_retries(cls.__init__);
        }
    }
    return True;
}

glob SDK_RETRIES_PINNED: bool = pin_sdk_retries();

# Tried in order (litellm Router fallback). NVIDIA retired
# meta/llama-3.1-8b-instruct on 2026-08-26 and nv-mistralai/mistral-nemo-12b
# answers 404 on our key, so the NIM chain is mistral-nemotron → gpt-oss-20b.
# Groq's gpt-oss-20b (strict json_schema, ~1k tok/s) leads when GROQ_API_KEY is
# set. CIVICMESH_LLM_MODELS (comma-separated litellm ids) overrides everything.
glob NIM_MODELS: list[str] = [
    "nvidia_nim/mistralai/mistral-nemotron",
    "nvidia_nim/openai/gpt-oss-20b"
];
glob GROQ_MODELS: list[str] = ["groq/openai/gpt-oss-20b"];

def build_pool_models -> list {
    raw = str(os.environ.get("CIVICMESH_LLM_MODELS", "")).strip();
    names: list[str] = [];
    if raw {
        names = [n.strip() for n in raw.split(",") if n.strip()];
    } else {
        if str(os.environ.get("GROQ_API_KEY", "")).strip() {
            names = names + list(GROQ_MODELS);
        }
        names = names + list(NIM_MODELS);
    }
    models: list = [Model(model_name=n) for n in names];
    featherless_key = str(os.environ.get("FEATHERLESS_API_KEY", "")).strip();
    if featherless_key {
        models.append(Model(
            model_name="featherless_ai/meta-llama/Llama-3.1-8B-Instruct",
            api_key=featherless_key
        ));
    }
    return models;
}

"""Litellm ids in fallback order, for telemetry display."""
def pool_model_names -> list {
    return [str(m.model_name) for m in build_pool_models()];
}

"""Belt and braces: also pin max_retries=0 in each deployment's litellm_params.

(Not sufficient on its own for NIM — the provider drops the param; see
pin_sdk_retries above, which is what actually stops the retries.)
"""
def without_sdk_retries(pool: Any) -> Any {
    try {
        for dep in list(pool._router.model_list) {
            dep["litellm_params"]["max_retries"] = 0;
        }
    } except Exception as _ex {}
    return pool;
}

# Sync path: the user is waiting (the walker also enforces a 3.5 s deadline).
glob fast_pool = without_sdk_retries(ModelPool(models=build_pool_models(), strategy="fallback", num_retries=0, timeout=5.0));
# Async path: nobody is blocked; allow one slow model before giving up.
glob narrate_pool = without_sdk_retries(ModelPool(models=build_pool_models(), strategy="fallback", num_retries=0, timeout=8.0));

# Long-tail languages: Gemma 4 (pre-trained on 140+ languages, on NVIDIA NIM)
# leads, then the default chain. CIVICMESH_POLYGLOT_MODELS overrides the lead.
glob POLYGLOT_MODELS: list[str] = ["nvidia_nim/google/gemma-4-31b-it"];

def build_polyglot_models -> list {
    raw = str(os.environ.get("CIVICMESH_POLYGLOT_MODELS", "")).strip();
    lead: list[str] = [n.strip() for n in raw.split(",") if n.strip()] if raw else list(POLYGLOT_MODELS);
    rest = [m for m in build_pool_models() if str(m.model_name) not in lead];
    return [Model(model_name=n) for n in lead] + rest;
}

def polyglot_model_names -> list {
    return [str(m.model_name) for m in build_polyglot_models()];
}

glob polyglot_pool = without_sdk_retries(ModelPool(models=build_polyglot_models(), strategy="fallback", num_retries=0, timeout=9.0));

# ---------- types kept for walker interfaces ----------

obj NeedProfile {
    has category: str = "",
        urgency: str = "within_weeks",
        family_size: int = 1,
        income_bracket: str = "",
        location_zip: str = "",
        language: str = "en",
        details: str = "";
}

sem NeedProfile is "Structured snapshot of one user's stated need plus demographic context.";

obj EscalationContext {
    has trigger_reason: str = "",
        profile: NeedProfile = NeedProfile(),
        denial_reasons: list[str] = [],
        urgency_level: str = "within_weeks";
}

sem EscalationContext is "Why escalation fired (no viable program, or every application denied) plus the user's profile.";

# ---------- sync: understand ----------

"""Structured reading of a message the deterministic parser couldn't route."""
obj UnderstoodNeed {
    has category: str = "",
        language: str = "en",
        urgency: str = "within_weeks",
        monthly_income: int = -1,
        household_size: int = 0,
        age: int = 0,
        state: str = "",
        citizenship: str = "",
        english_summary: str = "";
}

sem UnderstoodNeed.category is "Primary need. Exactly one of: 'housing', 'food', 'healthcare', 'legal'. Empty string only if the message asks for none of these.";
sem UnderstoodNeed.language is "ISO 639-1 code of the language the message is written in (e.g. 'en', 'es', 'vi', 'zh', 'ar').";
sem UnderstoodNeed.urgency is "One of 'immediate' (tonight / danger / no food), 'within_days', 'within_weeks'.";
sem UnderstoodNeed.monthly_income is "Household income per month in USD if stated, else -1. Convert hourly/weekly/yearly amounts to monthly.";
sem UnderstoodNeed.household_size is "People in the household including the writer, 0 if not stated.";
sem UnderstoodNeed.age is "Writer's age in years, 0 if not stated.";
sem UnderstoodNeed.state is "Two-letter US state code if a US place is mentioned, else empty.";
sem UnderstoodNeed.citizenship is "One of 'citizen', 'eligible_immigrant' (green card), 'humanitarian' (refugee, asylee, parolee), 'non_citizen', or '' if not mentioned.";
sem UnderstoodNeed.english_summary is "One short English sentence describing what the person needs.";

"""Read a help request in any language and extract the need and facts that are explicitly stated. Never guess values that are not in the text."""
def understand_message(message: str) -> UnderstoodNeed by fast_pool();

sem understand_message.message is "A person's message to a social-services navigator, in any language.";

# ---------- async: narrate ----------

"""Short localized narration of results the engine already computed."""
obj Narration {
    has message: str = "",
        chips: list[str] = [];
}

sem Narration.message is "Two or three warm, plain sentences in the target language: acknowledge the situation in one clause, name the first program to contact and why, and end with the follow-up question if one is given. No new facts, programs, numbers or phone numbers beyond those in `facts`. No markdown.";
sem Narration.chips is "The follow-up suggestions translated into the target language, same count and order as given. Return them unchanged if the target language is English. Keep program names (SNAP, WIC, Medicaid, Section 8) as they are.";

"""Write the reply for a social-services navigator from pre-computed facts. The facts are authoritative: do not add programs, eligibility claims, numbers or phone numbers that are not in them. The person's own words are deliberately not provided."""
def narrate_turn(language: str, facts: str, chips: list[str]) -> Narration by narrate_pool();

sem narrate_turn.language is "Language to write in, as 'Name (code)', e.g. 'Tamil (ta)'. If 'auto', write in plain English.";
sem narrate_turn.facts is "Engine output: matched programs with reasons, the first step, and the follow-up question. Authoritative.";
sem narrate_turn.chips is "Follow-up suggestion chips in English to translate.";

"""Same contract as narrate_turn, served by the polyglot pool for long-tail languages."""
def narrate_turn_polyglot(language: str, facts: str, chips: list[str]) -> Narration by polyglot_pool();

sem narrate_turn_polyglot.language is "Language to write in, as 'Name (code)', e.g. 'Tigrinya (ti)', 'Kurdish (Sorani) (ckb)'. If 'auto', write in plain English.";
sem narrate_turn_polyglot.facts is "Engine output: matched programs with reasons, the first step, and the follow-up question. Authoritative.";
sem narrate_turn_polyglot.chips is "Follow-up suggestion chips in English to translate.";
