"""CivicMesh graph node definitions.

All six node types in the schema, plus a semstring on every field.
The semstrings are what the byLLM router uses to ground walker reasoning
when it inspects the graph at runtime - keep them dense and unambiguous.
"""

node PersonNode {
    has user_id: str = "",
        language: str = "en",
        location_zip: str = "",
        income_bracket: str = "",
        family_size: int = 1,
        preferred_contact: str = "phone",
        created_at: str = "";
}

sem PersonNode is "A vulnerable individual seeking assistance. Root of every session subgraph. Carries the profile fields used by EligibilityWalker to filter ResourceNodes.";
sem PersonNode.user_id is "Stable identifier tied to the authenticated session. Used to look up a returning user's prior ApplicationNodes.";
sem PersonNode.language is "ISO 639-1 language code (e.g. en, es, fr, vi) detected from the user's first message. All walker responses must be produced in this language.";
sem PersonNode.location_zip is "US zip code (5 digits) or city name. Used for proximity matching against ResourceNode.address and for state/county residency rules on EligibilityRuleNode.";
sem PersonNode.income_bracket is "Annual household income range. One of: '0-15k', '15k-30k', '30k-50k', '50k+'. Compared against EligibilityRuleNode.income_limit_annual during eligibility scoring.";
sem PersonNode.family_size is "Number of people in the household, including the user. Compared against EligibilityRuleNode.min_family_size and used to size SNAP/WIC/housing allocations.";
sem PersonNode.preferred_contact is "How the person wants follow-up to happen. One of: 'phone', 'email', 'in-person', 'online'. Drives which ResourceNode contact field the ActionPlan should surface first.";
sem PersonNode.created_at is "ISO 8601 timestamp of when this PersonNode was first created. Used to distinguish first-time vs returning users in session summaries.";

node NeedNode {
    has category: str = "",
        urgency: str = "within_weeks",
        details: str = "",
        created_at: str = "";
}

sem NeedNode is "A discrete need expressed by the PersonNode during conversation. One PersonNode can have many NeedNodes - e.g. housing + food + healthcare simultaneously.";
sem NeedNode.category is "Top-level domain of the need. One of: 'housing', 'food', 'healthcare', 'legal'. Must match ResourceNode.category exactly so EligibilityWalker can join the two sets.";
sem NeedNode.urgency is "How quickly the user needs the resource. One of: 'immediate' (homeless tonight, no food today, crisis), 'within_days' (eviction notice, prescription out), 'within_weeks' (long-term housing search, ongoing benefits). Drives ordering in ActionPlan.";
sem NeedNode.details is "Free-form description in the user's own words. Preserved verbatim for the LLM to pick up nuance the categorical fields lose - e.g. 'I have a service dog' or 'I am undocumented'.";
sem NeedNode.created_at is "ISO 8601 timestamp when the need was first surfaced in conversation. Lets the system track which needs are still open vs already routed.";

node ResourceNode {
    has agency_name: str = "",
        category: str = "",
        capacity: str = "open",
        languages_supported: list[str] = [],
        contact_phone: str = "",
        contact_email: str = "",
        address: str = "",
        online_url: str = "",
        description: str = "";
}

sem ResourceNode is "A real-world agency, program, or service that can fulfill a NeedNode. Connected to EligibilityRuleNode via governed_by, and to NeedNode via eligible_for after matching.";
sem ResourceNode.agency_name is "Official name of the agency or program (e.g. 'Section 8 Housing Choice Voucher', 'Catholic Charities Food Pantry'). Acts as a natural primary key - the seed loader treats it as unique.";
sem ResourceNode.category is "Domain of service provided. One of: 'housing', 'food', 'healthcare', 'legal'. Must match NeedNode.category for the resource to be considered.";
sem ResourceNode.capacity is "Current intake status. One of: 'open' (accepting now), 'waitlist' (apply but expect delay), 'closed' (do not refer). The router demotes 'closed' to escalation paths only.";
sem ResourceNode.languages_supported is "List of ISO 639-1 codes the agency can serve. PersonNode.language must appear here, or the ActionPlan must include an interpreter referral.";
sem ResourceNode.contact_phone is "Primary phone number (digits and standard punctuation). Preferred entry-point for users with preferred_contact='phone'.";
sem ResourceNode.contact_email is "Public intake email address. Empty string when the agency does not publish one.";
sem ResourceNode.address is "Street address including city, state, zip. Used for proximity ranking against PersonNode.location_zip.";
sem ResourceNode.online_url is "Public-facing intake URL or program page. The ActionPlan deep-links to this for users with preferred_contact='online'.";
sem ResourceNode.description is "One-paragraph summary of what the resource provides, in plain language. The LLM uses this to explain choices to the user.";

node EligibilityRuleNode {
    has rule_id: str = "",
        income_limit_annual: int = 0,
        residency_requirement: str = "none",
        min_family_size: int = 0,
        citizenship_required: bool = False,
        age_min: int = 0,
        age_max: int = 0,
        exceptions: str = "",
        criteria_summary: str = "";
}

sem EligibilityRuleNode is "The structured eligibility criteria for a ResourceNode. Read by check_eligibility() to score how well a PersonNode's profile matches.";
sem EligibilityRuleNode.rule_id is "Stable identifier for this rule, typically '<agency_slug>-rule'. Used so multiple resources can share or reference the same rule without duplication.";
sem EligibilityRuleNode.income_limit_annual is "Maximum allowed annual household income in USD. A value of 0 means there is no income limit. Compared against the upper bound of PersonNode.income_bracket.";
sem EligibilityRuleNode.residency_requirement is "Geographic scope required for eligibility. One of: 'state', 'county', 'city', 'none'. Matched against PersonNode.location_zip.";
sem EligibilityRuleNode.min_family_size is "Minimum number of household members required. 0 means no minimum. Some programs (e.g. family shelters) require >= 2.";
sem EligibilityRuleNode.citizenship_required is "True if the program legally requires US citizenship or specific immigration status. False for programs that serve everyone regardless of status (food banks, ERs, many legal aid clinics).";
sem EligibilityRuleNode.age_min is "Minimum applicant age in years. 0 means no minimum. Used by youth/senior-specific programs.";
sem EligibilityRuleNode.age_max is "Maximum applicant age in years. 0 means no maximum. Used by youth-only programs.";
sem EligibilityRuleNode.exceptions is "Free-form description of edge cases, waivers, and special populations the rule treats differently. The LLM consults this for borderline matches before declaring ineligibility.";
sem EligibilityRuleNode.criteria_summary is "Human-readable one-sentence summary of the rule, suitable for LLM prompts and user-facing explanations. The primary surface check_eligibility() reads.";

node FormNode {
    has form_id: str = "",
        form_name: str = "",
        url: str = "",
        required_documents: list[str] = [],
        deadline_type: str = "rolling",
        submission_method: str = "online",
        estimated_minutes: int = 30;
}

sem FormNode is "An application form or intake artifact the user must complete to access the ResourceNode. Reached via the requires_form edge from EligibilityRuleNode.";
sem FormNode.form_id is "Stable identifier for the form (e.g. 'snap-application-il', 'hud-50058'). Treated as unique by the seed loader.";
sem FormNode.form_name is "Human-readable form name (e.g. 'SNAP Application', 'HUD-50058 Family Report'). Surfaced to the user verbatim in the ActionPlan.";
sem FormNode.url is "Public URL where the form can be downloaded, started, or submitted online. Empty string if no online version exists.";
sem FormNode.required_documents is "List of document names the user must gather before submitting (e.g. 'Photo ID', 'Proof of income', 'Birth certificate'). Drives the documents_needed field of ActionStep.";
sem FormNode.deadline_type is "Submission cadence. One of: 'rolling' (any time), 'monthly' (specific day each month), 'annual' (yearly cycle), 'one_time' (single window). Drives deadline_label in ActionStep.";
sem FormNode.submission_method is "How the completed form is delivered. One of: 'online', 'mail', 'in_person', 'phone'. Should match PersonNode.preferred_contact when feasible.";
sem FormNode.estimated_minutes is "Realistic time to complete the form for a first-time applicant, in minutes. Surfaced to users so they can budget time.";

node ApplicationNode {
    has application_id: str = "",
        status: str = "pending",
        resource_name: str = "",
        applied_at: str = "",
        updated_at: str = "",
        denial_reason: str = "",
        next_step_hint: str = "",
        notes: str = "";
}

sem ApplicationNode is "Represents one PersonNode's attempt to access one ResourceNode. Persists across sessions so returning users see their history. Connected to PersonNode via applied_to.";
sem ApplicationNode.application_id is "Stable identifier for this application instance, typically a UUID. Used as the natural primary key for ApplicationNodes.";
sem ApplicationNode.status is "Current lifecycle state. One of: 'pending' (not yet submitted), 'applied' (submitted, awaiting decision), 'approved', 'denied', 'withdrawn'. Drives session summary categorization.";
sem ApplicationNode.resource_name is "Denormalized copy of the linked ResourceNode.agency_name. Allows quick display in session summaries without an extra graph traversal.";
sem ApplicationNode.applied_at is "ISO 8601 timestamp of when the application moved into 'applied' status. Empty for pending applications.";
sem ApplicationNode.updated_at is "ISO 8601 timestamp of the most recent status change. Used to detect stale applications that may need follow-up.";
sem ApplicationNode.denial_reason is "Free-form reason text populated only when status='denied'. Read by generate_denial_next_step() to produce an empathetic, actionable response.";
sem ApplicationNode.next_step_hint is "LLM-generated guidance describing what the user should do next given the current status. Refreshed each time the status updates.";
sem ApplicationNode.notes is "Free-form notes the user or caseworker has attached to this application. Preserved verbatim; the LLM may reference it but never overwrites it.";
