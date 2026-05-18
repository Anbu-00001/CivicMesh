"""byLLM function stubs for CivicMesh.

Phase 1 ships only the typed signatures (and the structured return types that
walkers will consume). The actual prompt templates and walker integration are
added in Phase 2. Defining the types here means walkers can import these names
today and the LLM router stays grounded by stable, named schemas.

The ModelPool is configured here as a module-level glob. Adding a fallback
model in Phase 2 is a one-line change to the `models=[...]` list - no
call-site edits required. Default model parameters come from jac.toml.
"""

import from byllm.lib { Model, ModelPool }

glob pool = ModelPool(
    models=[Model(model_name="nvidia_nim/meta/llama-3.1-8b-instruct")],
    strategy="fallback",
);

# ---------- Structured return types ----------

"""Profile of a person's situation, extracted from free-form conversation.

Every field has a default so the LLM can produce a partial profile when the
user has not volunteered everything yet; downstream walkers treat empty
strings and zero values as "unknown" rather than zero.
"""
obj NeedProfile {
    has category: str = "",
        urgency: str = "within_weeks",
        family_size: int = 1,
        income_bracket: str = "",
        location_zip: str = "",
        language: str = "en",
        details: str = "";
}

sem NeedProfile is "Structured snapshot of one user's stated need plus the demographic context required to evaluate eligibility. Produced by extract_need_profile() and consumed by check_eligibility() and generate_action_plan().";
sem NeedProfile.category is "Top-level need domain. One of: 'housing', 'food', 'healthcare', 'legal'.";
sem NeedProfile.urgency is "How quickly help is required. One of: 'immediate', 'within_days', 'within_weeks'.";
sem NeedProfile.family_size is "Household size, including the user. Used for eligibility scoring against EligibilityRuleNode.min_family_size.";
sem NeedProfile.income_bracket is "Annual household income range. One of: '0-15k', '15k-30k', '30k-50k', '50k+'.";
sem NeedProfile.location_zip is "User's zip code or city. Used to apply state/county/city residency rules.";
sem NeedProfile.language is "ISO 639-1 code the user is communicating in. All downstream responses must be produced in this language.";
sem NeedProfile.details is "Free-form description of the user's situation in their own words. Preserves nuance the categorical fields lose.";

"""Per-resource eligibility evaluation result.

The match_score is 0-100; >= 70 typically means the user should apply, 40-70
means apply with documentation gaps to address, < 40 means look elsewhere.
"""
obj EligibilityResult {
    has resource_name: str = "",
        match_score: int = 0,
        matched_criteria: list[str] = [],
        missing_criteria: list[str] = [],
        is_eligible: bool = False;
}

sem EligibilityResult is "Per-resource outcome of check_eligibility(). Walkers use is_eligible to filter and match_score to rank.";
sem EligibilityResult.resource_name is "ResourceNode.agency_name this evaluation refers to.";
sem EligibilityResult.match_score is "Confidence score from 0-100. 70+ = apply now, 40-70 = apply with documentation gaps, < 40 = look elsewhere.";
sem EligibilityResult.matched_criteria is "Human-readable list of criteria the user clearly meets. Shown to the user verbatim.";
sem EligibilityResult.missing_criteria is "Human-readable list of criteria the user does not meet or has not yet documented. Drives ActionStep.documents_needed.";
sem EligibilityResult.is_eligible is "True if the user likely qualifies. Walkers use this to gate the eligible_for edge.";

"""One step in an action plan - a concrete thing the user should do next."""
obj ActionStep {
    has step_number: int = 0,
        agency_name: str = "",
        action_description: str = "",
        documents_needed: list[str] = [],
        deadline_label: str = "",
        contact_info: str = "",
        estimated_minutes: int = 0,
        online_url: str = "";
}

sem ActionStep is "A single concrete action the user can take, drawn from a matched ResourceNode and its FormNode. Walkers concatenate these into an ActionPlan.";
sem ActionStep.step_number is "1-indexed ordinal of this step inside its ActionPlan. Used by the UI to render numbered lists.";
sem ActionStep.agency_name is "Agency the user is engaging in this step. Surfaced verbatim.";
sem ActionStep.action_description is "One-sentence imperative description of what the user should do, in the user's language.";
sem ActionStep.documents_needed is "List of documents the user must bring or upload for this step. Sourced from FormNode.required_documents.";
sem ActionStep.deadline_label is "Human-readable deadline phrasing (e.g. 'Apply by the 15th of each month', 'Open year-round'). Derived from FormNode.deadline_type.";
sem ActionStep.contact_info is "Best contact-string for this step, chosen based on PersonNode.preferred_contact. Phone number, email, or address.";
sem ActionStep.estimated_minutes is "How long this step is expected to take. Mirrors FormNode.estimated_minutes.";
sem ActionStep.online_url is "Deep-link to the online intake or form, when applicable. Empty string if step is not online.";

"""Ordered plan composed of ActionSteps plus a top-line summary."""
obj ActionPlan {
    has steps: list[ActionStep] = [],
        summary: str = "";
}

sem ActionPlan is "Top-level plan returned to the user. The summary is shown first, then steps render as a numbered list.";
sem ActionPlan.steps is "ActionSteps in the order the user should attempt them. Generated by generate_action_plan().";
sem ActionPlan.summary is "One-paragraph plain-language summary of what this plan accomplishes and why these steps were chosen.";

"""Context for triggering an escalation - dead-end, all-denied, or crisis."""
obj EscalationContext {
    has trigger_reason: str = "",
        profile: NeedProfile = NeedProfile(),
        denial_reasons: list[str] = [],
        urgency_level: str = "within_weeks";
}

sem EscalationContext is "Bundle of state passed to compose_escalation_message() when no resource path is viable. Drives crisis lines, appeal hints, and personalized messaging.";
sem EscalationContext.trigger_reason is "Free-form description of why escalation fired (e.g. 'all resources are full', 'every application denied', 'user reported active crisis').";
sem EscalationContext.profile is "Snapshot of the user's NeedProfile at the moment of escalation. Used to personalize tone and language.";
sem EscalationContext.denial_reasons is "List of denial reasons collected from prior ApplicationNodes. Each becomes a candidate for appeal advice.";
sem EscalationContext.urgency_level is "Mirrors NeedNode.urgency. 'immediate' escalations include crisis hotline numbers; lower urgency levels stay informational.";

"""Message produced for a dead-end or all-denied situation."""
obj EscalationMessage {
    has crisis_resources: list[str] = [],
        appeal_options: list[str] = [],
        personalized_message: str = "",
        is_emergency: bool = False;
}

sem EscalationMessage is "Output of compose_escalation_message(). The UI renders crisis_resources before everything else when is_emergency is True.";
sem EscalationMessage.crisis_resources is "Names and contact lines for 24/7 crisis resources (988, NDV hotline, SAMHSA) appropriate to the user's situation.";
sem EscalationMessage.appeal_options is "List of one-sentence appeal or alternative paths the user can try next, given their denial reasons.";
sem EscalationMessage.personalized_message is "Empathetic, plain-language message addressed directly to the user. Acknowledges the dead-end without minimizing it.";
sem EscalationMessage.is_emergency is "True when the user's situation warrants immediate crisis intervention. UI surfaces crisis_resources first.";

"""Language detection result for the user's first message."""
obj LanguageProfile {
    has detected_language: str = "en",
        confidence: float = 0.0,
        translated_intent: str = "";
}

sem LanguageProfile is "Output of detect_language_and_extract(). Walkers use detected_language to set PersonNode.language for all subsequent responses.";
sem LanguageProfile.detected_language is "ISO 639-1 code (e.g. 'en', 'es', 'vi') of the user's input.";
sem LanguageProfile.confidence is "0.0 - 1.0 confidence of the detection. Values under 0.6 trigger a clarification turn.";
sem LanguageProfile.translated_intent is "English translation of the user's first message, so downstream prompts stay grounded even in non-Latin scripts.";

"""Summary of a returning user's prior session state."""
obj SessionSummary {
    has approved: list[str] = [],
        pending: list[str] = [],
        denied: list[str] = [],
        next_recommended_step: str = "";
}

sem SessionSummary is "Output of summarize_session(). Drives the welcome message a returning user sees on their next visit.";
sem SessionSummary.approved is "Agency names where ApplicationNode.status='approved'. Surfaced as wins.";
sem SessionSummary.pending is "Agency names where status is 'pending' or 'applied'. Surfaced with a 'check status' prompt.";
sem SessionSummary.denied is "Agency names where status='denied'. Pairs with next_recommended_step to keep momentum.";
sem SessionSummary.next_recommended_step is "Single sentence advising the user what to focus on first in this session.";

# ---------- LLM function stubs ----------

"""Extract a structured NeedProfile from a free-form, possibly multilingual conversation transcript."""
def extract_need_profile(conversation: str) -> NeedProfile by pool();

sem extract_need_profile.conversation is "Full transcript of the user's chat turns so far, in whatever language they typed. May contain mixed scripts and informal phrasing; the model must lift a structured NeedProfile from it without losing nuance.";

"""Score how well a profile satisfies one resource's eligibility rule. Return matched and missing criteria plus a 0-100 score."""
def check_eligibility(
    profile: NeedProfile,
    criteria_summary: str,
    income_limit: int,
    citizenship_required: bool,
    residency_req: str,
    age_min: int,
    age_max: int,
    exceptions: str
) -> EligibilityResult by pool();

sem check_eligibility.profile is "The user's NeedProfile snapshot. Provides demographic context used to evaluate every criterion.";
sem check_eligibility.criteria_summary is "Human-readable summary of the resource's EligibilityRuleNode.criteria_summary. Primary surface the model reads when reasoning about the match.";
sem check_eligibility.income_limit is "EligibilityRuleNode.income_limit_annual in USD. 0 means no income limit and any bracket should match on income.";
sem check_eligibility.citizenship_required is "True if the resource legally requires US citizenship. Drives whether undocumented users should be excluded.";
sem check_eligibility.residency_req is "Residency scope required by the resource. One of: 'state', 'county', 'city', 'none'. Matched against profile.location_zip.";
sem check_eligibility.age_min is "Minimum applicant age accepted by the resource. 0 means no minimum.";
sem check_eligibility.age_max is "Maximum applicant age accepted by the resource. 0 means no maximum.";
sem check_eligibility.exceptions is "Free-form description of waivers and edge cases the resource grants. Consult before declaring ineligibility on a borderline match.";

"""Generate an ordered ActionPlan from a list of eligible resource names plus the user's profile. Order by urgency and deadline."""
def generate_action_plan(eligible_resources: list[str], profile: NeedProfile) -> ActionPlan by pool();

sem generate_action_plan.eligible_resources is "List of ResourceNode.agency_name strings that passed eligibility scoring. Order does not matter; the model is expected to re-sequence by urgency and deadline.";
sem generate_action_plan.profile is "The user's NeedProfile. Drives ordering: 'immediate' urgency comes first, language and preferred_contact shape the action_description tone.";

"""Compose an empathetic escalation message for dead-end or all-denied scenarios.

Uses ReAct-style tool calling to consult the live graph and assess safety risk.
The on_iteration callback fires between steps so the EscalationWalker can stream
progress to the WebSocket client and guard against doom-loops.

CRITICAL — language handling: write personalized_message AND appeal_options
ENTIRELY in `context.profile.language` (ISO 639-1 code). Do NOT mix English
and the target language in any single string — a long message that's half
English looks broken in the chat UI. If context.profile.language is empty,
'en', or 'english', write in English. crisis_resources hotline names and
phone numbers stay canonical (e.g. "988 Suicide and Crisis Lifeline") since
those are recognized search strings users would google."""
def compose_escalation_message(
    context: EscalationContext,
    tools: list = [],
    on_iteration: any = None
) -> EscalationMessage by pool();

sem compose_escalation_message.context is "EscalationContext bundle describing why escalation fired plus the user's NeedProfile. The primary input the model reasons over. context.profile.language dictates the language of personalized_message and appeal_options — do not translate after.";
sem compose_escalation_message.tools is "List of ReAct tool callables the model may invoke to consult the live graph (emergency resources, appeal orgs, safety risk). Order is not meaningful.";
sem compose_escalation_message.on_iteration is "Callback fired between ReAct iterations. Returns IterationAction.CONTINUE or ABORT_WITH_SUMMARY so the host walker can stream progress and cap runaway loops.";

"""Detect the language of the user's first message and translate intent into English for downstream prompts."""
def detect_language_and_extract(message: str) -> LanguageProfile by pool();

sem detect_language_and_extract.message is "The user's first chat message, exactly as typed. May be in any language and any script; the model must detect language and translate intent into English.";

"""Produce a short, empathetic next-step hint after a denial, given the agency, the denial reason, and the user's profile."""
def generate_denial_next_step(resource_name: str, denial_reason: str, profile: NeedProfile) -> str by pool();

sem generate_denial_next_step.resource_name is "ResourceNode.agency_name that denied the application. Surfaced verbatim in the hint.";
sem generate_denial_next_step.denial_reason is "Free-form ApplicationNode.denial_reason text. The model maps this to a concrete next-step action.";
sem generate_denial_next_step.profile is "The user's NeedProfile. Drives tone, language, and whether to suggest appeal vs alternative.";

"""Summarize a returning user's prior session: approved, pending, denied applications, plus one recommended next action."""
def summarize_session(
    approved: list[str],
    pending: list[str],
    denied: list[str],
    profile: NeedProfile
) -> SessionSummary by pool();

sem summarize_session.approved is "Agency names where ApplicationNode.status='approved'. The model frames these as wins in the welcome message.";
sem summarize_session.pending is "Agency names where status is 'pending' or 'applied'. Pair with a 'check status' prompt.";
sem summarize_session.denied is "Agency names where status='denied'. Pair with next_recommended_step to keep momentum.";
sem summarize_session.profile is "The user's NeedProfile. Drives language and tone of the summary.";

"""Translate a batch of English strings into the target language. CRITICAL: translate EVERY SINGLE string in the input list — do not skip any, do not leave any in English. Return a list of the SAME LENGTH as the input, in the SAME ORDER, with each entry being the translation of the corresponding input entry. Preserve meaning, tone, punctuation, emoji, and rhetorical question marks. If target_language is empty, 'en', or 'english', return the input unchanged. Target language may be an ISO code or natural-language name like 'hi', 'es', 'Hindi', 'Spanish', 'German', 'fr', 'French'. Even if a single string already appears to be in the target language, still include it in the output at the same index."""
def translate_batch(texts: list[str], target_language: str) -> list[str] by pool();

sem translate_batch.texts is "Ordered list of UI / bot strings in English. The model must return exactly this many entries in exactly this order, each translated.";
sem translate_batch.target_language is "ISO 639-1 code or natural-language name of the user's language (e.g. 'es', 'hi', 'Hindi'). Empty / 'en' / 'english' means pass through unchanged.";
