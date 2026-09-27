"""Persona: Undocumented parent of three children seeking healthcare.

The action plan should not surface Medicaid (citizenship_required=true in seed
data). Free clinics and FQHCs should remain in scope.
"""

import from walkers.intake { IntakeWalker }
import from walkers.seed { SeedWalker }

test "undocumented_healthcare" {
    conversation = "I need help with healthcare for my children. I do not have social security number. I have 3 children ages 2, 5, and 8. We need to see a doctor but cannot afford it. I work but I have no papers. We live in Houston area.";

    root spawn SeedWalker(user_id="test_persona_002");
    intake = root spawn IntakeWalker(
        conversation=conversation,
        user_id="test_persona_002"
    );
    assert len(intake.reports) > 0;
    result = intake.reports[-1];

    assert result["profile"]["category"] == "healthcare";

    assert len(result["matches"]) > 0;
    # Full Medicaid requires qualifying status: never a first step, never
    # "likely"/"possible" for an undocumented adult (emergency Medicaid and
    # FQHCs are the routes the engine should surface instead).
    for s in result["plan"]["steps"] {
        assert not str(s["agency_name"]).lower().startswith("medicaid");
    }
    for m in result["matches"] {
        if str(m["resource_name"]).lower().startswith("medicaid") {
            assert m["tier"] not in ["likely", "possible"];
        }
    }

    print("✓ Persona: Undocumented individual — PASSED");
}
