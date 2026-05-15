"""CivicMesh typed edge definitions.

Edges carry the relationship semantics that walkers traverse. Direction matters:
the source-to-target arrow in the comments is the directed edge as it exists
in the graph, and walkers follow that direction unless reversed explicitly.
"""

# PersonNode -> NeedNode
edge has_need {}
sem has_need is "A PersonNode currently has this NeedNode open. Created when extract_need_profile() lifts a need from conversation. Persists until the underlying need is resolved.";

# NeedNode -> ResourceNode
edge eligible_for {}
sem eligible_for is "A NeedNode could be fulfilled by this ResourceNode. Created by the EligibilityWalker after check_eligibility() returns is_eligible=true.";

# ResourceNode -> EligibilityRuleNode
edge governed_by {}
sem governed_by is "A ResourceNode is governed by this EligibilityRuleNode. Static schema relationship installed by the seed loader; not modified at runtime.";

# EligibilityRuleNode -> FormNode
edge requires_form {}
sem requires_form is "An EligibilityRuleNode requires this FormNode to be completed. Static schema relationship installed by the seed loader.";

# PersonNode -> ApplicationNode
edge applied_to {}
sem applied_to is "A PersonNode has filed (or started) an application captured in this ApplicationNode. Persists across sessions so returning users see their history.";
