"""CivicMesh entry point.

Phase 1: scaffold only. The schema, seed loader, and byLLM stubs are wired up
here so that `jac start app.jac --dev` boots without errors. Walkers and the
client UI ship in Phase 2 and Phase 3.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode, FormNode, ApplicationNode }
import from graph.edges { has_need, eligible_for, governed_by, requires_form, applied_to }
import from llm.stubs { NeedProfile, EligibilityResult, ActionStep, ActionPlan, EscalationContext, EscalationMessage, LanguageProfile, SessionSummary }

with entry {
    print("CivicMesh Phase 1: schema, edges, and byLLM stubs loaded.");
}
