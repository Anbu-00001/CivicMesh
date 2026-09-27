"""CivicMesh typed edge definitions.

Edges carry the relationship semantics that walkers traverse. Direction matters:
the source-to-target arrow in the comments is the directed edge as it exists
in the graph, and walkers follow that direction unless reversed explicitly.
"""

# PersonNode -> NeedNode
edge has_need {}
sem has_need is "A PersonNode currently has this NeedNode open. Created when extract_need_profile() lifts a need from conversation. Persists until the underlying need is resolved.";

# NeedNode -> ResourceNode
edge eligible_for {
    has tier: str = "",
        p_eligible: float = 0.0,
        rank: int = 0,
        benefit_monthly: int = 0;
}
sem eligible_for is "The engine's verdict for one need against one program, persisted: EligibilityWalker writes one edge per top match (tier, P(eligible), rank, estimated monthly benefit). The Graph tab is a query over these edges.";
sem eligible_for.tier is "likely | possible | needs_info | unlikely — the calibrated abstention tier.";
sem eligible_for.p_eligible is "P(eligible) from engine/score.jac for this need.";
sem eligible_for.rank is "0-based position in the ranked answer the user saw.";

# ResourceNode -> EligibilityRuleNode
edge governed_by {}
sem governed_by is "A ResourceNode is governed by this EligibilityRuleNode. Static schema relationship installed by the seed loader; not modified at runtime.";

# EligibilityRuleNode -> FormNode
edge requires_form {}
sem requires_form is "An EligibilityRuleNode requires this FormNode to be completed. Static schema relationship installed by the seed loader.";

# PersonNode -> ApplicationNode
edge applied_to {}
sem applied_to is "A PersonNode has filed (or started) an application captured in this ApplicationNode. Persists across sessions so returning users see their history.";

# ResourceNode -> ResourceNode
# Carries the real-world "progression" between civic resources. Used by
# PathfinderWalker to discover multi-step escape paths when a user has
# zero direct eligibility matches. The payload fields ground each hop in
# real bureaucratic transitions so the LLM-rendered chain reads as
# concrete advice ("submit Form X, then your priority bumps for Y") rather
# than generic links.
edge leads_to {
    has transition_reason: str = "",
        typical_days: int = 30,
        difficulty: str = "moderate";
}

sem leads_to is "Real-world progression between civic resources. Pre-seeded with curated transitions (Emergency Shelter -> Transitional Housing -> Section 8 priority). PathfinderWalker walks these edges with BFS to surface 2-3 step escape paths when EligibilityWalker has no direct match.";
sem leads_to.transition_reason is "One-line plain-language explanation of why one resource leads to the next (e.g. 'Emergency Shelter intake auto-creates a Section 8 priority application'). Surfaced verbatim to the user as the path step's caption.";
sem leads_to.typical_days is "Realistic number of days the transition takes in practice. Used to estimate total path duration for the user.";
sem leads_to.difficulty is "Perceived friction of making this hop. One of: 'easy' (auto-flow), 'moderate' (paperwork), 'hard' (legal advocate recommended).";

# PersonNode -> SessionInsight
edge reflected_on {}
sem reflected_on is "Connects a PersonNode to a SessionInsight written after each chat turn (quality score, walkers that ran, LLM calls actually made). Read back by the Telemetry tab.";
