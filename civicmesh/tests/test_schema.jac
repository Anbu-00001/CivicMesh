"""Smoke tests for the CivicMesh schema.

These tests cover the Phase-1 contract: every node type can be instantiated,
every edge type can be created between the correct endpoints, the seed loader
populates the graph, and the LLM stub return types are constructible. Walker
behavior is intentionally not exercised here - that arrives in Phase 2 tests.

Run: `jac test tests/test_schema.jac`
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode, FormNode, ApplicationNode }
import from graph.edges { has_need, eligible_for, governed_by, requires_form, applied_to }
import from graph.seed_data { seed }
import from llm.stubs { NeedProfile, EligibilityResult, ActionStep, ActionPlan, LanguageProfile, SessionSummary }

test "node_instantiation" {
    person = PersonNode(
        user_id="u-001",
        language="en",
        location_zip="60601",
        income_bracket="0-15k",
        family_size=3,
        preferred_contact="phone",
        created_at="2026-05-15T00:00:00Z"
    );
    assert person.user_id == "u-001";
    assert person.family_size == 3;

    need = NeedNode(
        category="housing",
        urgency="immediate",
        details="Eviction notice received this morning.",
        created_at="2026-05-15T00:00:00Z"
    );
    assert need.category == "housing";
    assert need.urgency == "immediate";

    resource = ResourceNode(
        agency_name="Test Agency",
        category="housing",
        capacity="open",
        languages_supported=["en", "es"],
        contact_phone="555-0100",
        contact_email="",
        address="",
        online_url="",
        description="Schema smoke test agency."
    );
    assert resource.agency_name == "Test Agency";
    assert "en" in resource.languages_supported;

    rule = EligibilityRuleNode(
        rule_id="test-rule",
        income_limit_annual=25000,
        residency_requirement="state",
        min_family_size=0,
        citizenship_required=False,
        age_min=18,
        age_max=0,
        exceptions="",
        criteria_summary="Test rule."
    );
    assert rule.income_limit_annual == 25000;
    assert not rule.citizenship_required;

    form = FormNode(
        form_id="test-form",
        form_name="Test Form",
        url="",
        required_documents=["Photo ID"],
        deadline_type="rolling",
        submission_method="online",
        estimated_minutes=30
    );
    assert form.form_id == "test-form";
    assert form.estimated_minutes == 30;

    app_node = ApplicationNode(
        application_id="a-001",
        status="pending",
        resource_name="Test Agency",
        applied_at="",
        updated_at="",
        denial_reason="",
        next_step_hint="",
        notes=""
    );
    assert app_node.status == "pending";
}

test "edges_connect_correct_endpoints" {
    person = PersonNode(user_id="u-edges");
    need = NeedNode(category="food", urgency="within_days");
    resource = ResourceNode(agency_name="Edge Agency", category="food");
    rule = EligibilityRuleNode(rule_id="edge-rule");
    form = FormNode(form_id="edge-form");
    app_node = ApplicationNode(application_id="a-edges", status="pending");

    person +>: has_need() :+> need;
    need +>: eligible_for() :+> resource;
    resource +>: governed_by() :+> rule;
    rule +>: requires_form() :+> form;
    person +>: applied_to() :+> app_node;

    assert len([person ->: has_need :-> ]) == 1;
    assert len([need ->: eligible_for :-> ]) == 1;
    assert len([resource ->: governed_by :-> ]) == 1;
    assert len([rule ->: requires_form :-> ]) == 1;
    assert len([person ->: applied_to :-> ]) == 1;
}

test "seed_loader_populates_graph" {
    result = seed();
    total = result["total"];
    assert total >= 40;
    # On a fresh graph the loader inserts everything; on a re-run it skips
    # everything. Either outcome means the file content was processed.
    assert (result["inserted"] + result["skipped"]) == total;

    resources = [root --> [?:ResourceNode]];
    assert len(resources) >= 40;
}

test "llm_return_types_constructible" {
    profile = NeedProfile(
        category="legal",
        urgency="within_weeks",
        family_size=1,
        income_bracket="15k-30k",
        location_zip="10001",
        language="en",
        details="Need help with eviction defense."
    );
    assert profile.category == "legal";
    assert profile.language == "en";

    elig = EligibilityResult(
        resource_name="LSC",
        match_score=85,
        matched_criteria=["income"],
        missing_criteria=[],
        is_eligible=True
    );
    assert elig.is_eligible;
    assert elig.match_score == 85;

    step = ActionStep(
        step_number=1,
        agency_name="LSC",
        action_description="Call LSC intake line.",
        documents_needed=["Photo ID"],
        deadline_label="Open year-round",
        contact_info="2-1-1",
        estimated_minutes=45,
        online_url=""
    );
    plan = ActionPlan(steps=[step], summary="One step plan.");
    assert len(plan.steps) == 1;
    assert plan.steps[0].agency_name == "LSC";

    lang = LanguageProfile(detected_language="es", confidence=0.95, translated_intent="I need help.");
    assert lang.detected_language == "es";

    summary = SessionSummary(
        approved=["WIC"],
        pending=["SNAP"],
        denied=[],
        next_recommended_step="Follow up on SNAP application."
    );
    assert "WIC" in summary.approved;
}
