"""Persona: Undocumented parent of three children seeking healthcare.

The action plan should not surface Medicaid (citizenship_required=true in seed
data). Free clinics and FQHCs should remain in scope.
"""

import from walkers.intake { IntakeWalker }

test "undocumented_healthcare" {
    conversation = "I need help with healthcare for my children. I do not have social security number. I have 3 children ages 2, 5, and 8. We need to see a doctor but cannot afford it. I work but I have no papers. We live in Houston area.";

    intake = root spawn IntakeWalker(
        conversation=conversation,
        user_id="test_persona_002"
    );
    assert len(intake.reports) > 0;
    result = intake.reports[-1];

    assert result["profile"]["category"] == "healthcare";

    elig = result["eligibility_results"];
    assert "escalated" in elig;

    if not elig["escalated"] {
        steps = elig["action_plan"]["action_plan"]["steps"];
        assert len(steps) > 0;
        # Medicaid must not appear — its rule has citizenship_required=true.
        for s in steps {
            assert "medicaid" not in str(s["agency_name"]).lower();
        }
    }

    print("✓ Persona: Undocumented individual — PASSED");
}
