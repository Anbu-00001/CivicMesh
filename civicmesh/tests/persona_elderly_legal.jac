"""Persona: 72-year-old SSI recipient facing illegal eviction with a court date
in two weeks. Multi-session test: intake → mark first step applied →
MemoryWalker resumes with the new status intact.
"""

import from walkers.intake { IntakeWalker }
import from walkers.memory { MemoryWalker }

test "elderly_legal_session_memory" {
    conversation = "I am 72 years old and my landlord is trying to evict me illegally. I cannot afford a lawyer. I have lived in this apartment for 15 years. My only income is Social Security of about $1,200 per month. I need legal help urgently. The court date is in 2 weeks.";

    intake = root spawn IntakeWalker(
        conversation=conversation,
        user_id="test_persona_003"
    );
    assert len(intake.reports) > 0;
    result1 = intake.reports[-1];

    assert result1["profile"]["category"] == "legal";

    elig = result1["eligibility_results"];
    if not elig["escalated"] {
        steps = elig["action_plan"]["action_plan"]["steps"];
        if len(steps) > 0 {
            first_agency = str(steps[0]["agency_name"]);
            update_walker = root spawn MemoryWalker(
                user_id="test_persona_003",
                mode="update_status",
                resource_name=first_agency,
                new_status="applied"
            );
            assert len(update_walker.reports) > 0;
            update = update_walker.reports[0];
            assert update["updated"];
        }
    }

    mem = root spawn MemoryWalker(
        user_id="test_persona_003",
        mode="read_session"
    );
    assert len(mem.reports) > 0;
    session = mem.reports[0];
    assert session["has_history"];
    assert session["application_count"] > 0;
    assert len(session["pending"]) > 0 or len(session["approved"]) > 0;

    print("✓ Persona: Elderly legal + session memory — PASSED");
}
