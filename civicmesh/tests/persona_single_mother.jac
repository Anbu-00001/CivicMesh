"""Persona: Spanish-speaking single mother with two young children, $1,800/mo
income, 77001 (Houston), facing imminent eviction.

End-to-end pipeline check: IntakeWalker → EligibilityWalker → NavigationWalker
must surface housing or food resources, persist ApplicationNodes, and let a
follow-up MemoryWalker call read the session back.

Walker spawns return the walker instance; the `report` payload lives in
`walker.reports`. We always inspect the first report - that's the top-level
summary the walker emits on completion.
"""

import from walkers.intake { IntakeWalker }
import from walkers.memory { MemoryWalker }

test "single_mother_full_pipeline" {
    conversation = "Hola, soy madre soltera con 2 hijos pequenos. Necesito ayuda urgente con vivienda y comida. Gano aproximadamente $1,800 al mes. Vivimos en el codigo postal 77001 en Houston. Mis hijos tienen 4 y 7 anos. Estamos en riesgo de perder nuestro apartamento este mes.";

    intake = root spawn IntakeWalker(
        conversation=conversation,
        user_id="test_persona_001"
    );
    assert len(intake.reports) > 0;
    # Reports from child walkers (Navigation, Eligibility) flow into the
    # spawning walker's `.reports` list in completion order, so the IntakeWalker's
    # own top-level report is the last entry.
    result = intake.reports[-1];

    assert "profile" in result;
    assert result["profile"]["category"] in ["housing", "food"];
    assert result["language"] == "es";
    assert "eligibility_results" in result;

    elig = result["eligibility_results"];
    assert "escalated" in elig;

    if not elig["escalated"] {
        steps = elig["action_plan"]["action_plan"]["steps"];
        assert len(steps) > 0;
    }

    mem = root spawn MemoryWalker(
        user_id="test_persona_001",
        mode="read_session"
    );
    assert len(mem.reports) > 0;
    session = mem.reports[0];
    assert session["has_history"];
    assert session["application_count"] > 0;

    print("✓ Persona: Single mother — PASSED");
}
