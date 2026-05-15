"""CivicMesh entry point.

Phase 2: all five walkers (intake, eligibility, navigation, memory, escalation)
are imported so jac-scale auto-registers them as REST/WebSocket endpoints when
the dev server starts. The Phase 3 client block is added on top of this file.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode, FormNode, ApplicationNode }
import from graph.edges { has_need, eligible_for, governed_by, requires_form, applied_to }
import from llm.stubs { NeedProfile, EligibilityResult, ActionStep, ActionPlan, EscalationContext, EscalationMessage, LanguageProfile, SessionSummary }

import from walkers.intake { IntakeWalker }
import from walkers.eligibility { EligibilityWalker }
import from walkers.navigation { NavigationWalker }
import from walkers.memory { MemoryWalker }
import from walkers.escalation { EscalationWalker }

with entry {
    print("CivicMesh Phase 2: schema, byLLM stubs, and 5 walkers loaded.");
}
