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
    models=[Model(model_name="gemini/gemini-2.5-flash")],
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

"""Generate an ordered ActionPlan from a list of eligible resource names plus the user's profile. Order by urgency and deadline."""
def generate_action_plan(eligible_resources: list[str], profile: NeedProfile) -> ActionPlan by pool();

"""Compose an empathetic escalation message for dead-end or all-denied scenarios. Surfaces crisis resources when urgency='immediate'."""
def compose_escalation_message(context: EscalationContext) -> EscalationMessage by pool();

"""Detect the language of the user's first message and translate intent into English for downstream prompts."""
def detect_language_and_extract(message: str) -> LanguageProfile by pool();

"""Produce a short, empathetic next-step hint after a denial, given the agency, the denial reason, and the user's profile."""
def generate_denial_next_step(resource_name: str, denial_reason: str, profile: NeedProfile) -> str by pool();

"""Summarize a returning user's prior session: approved, pending, denied applications, plus one recommended next action."""
def summarize_session(
    approved: list[str],
    pending: list[str],
    denied: list[str],
    profile: NeedProfile
) -> SessionSummary by pool();
