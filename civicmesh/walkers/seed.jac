"""SeedWalker — idempotent per-user resource graph bootstrap.

jac-scale gives every authenticated user their own `root`. The CLI seed
loader at `graph/seed_data.jac` only writes to the global module root, so
freshly-registered users would otherwise see an empty graph and every
EligibilityWalker call would escalate with `zero_eligible_resources`.

This walker reads the same `data/resources.json` file and materializes 40
ResourceNode + EligibilityRuleNode + FormNode triples into the caller's
root. It's idempotent — re-running is a no-op once the resources are in.

The frontend calls this once on auth in `ClientApp.initAuth` before the
chat tab is rendered, so by the time the user sends their first prompt
the eligibility walker has the full resource catalog to score against.
"""

import json;
import os;

import from graph.nodes { ResourceNode, EligibilityRuleNode, FormNode, PersonNode, ApplicationNode }
import from graph.edges { governed_by, requires_form, leads_to, applied_to }


walker SeedWalker {
    # No demo-app or PersonNode seeding here — the real chat chain
    # produces ApplicationNodes via NavigationWalker, MemoryWalker writes
    # SessionInsights via CritiqueWalker, and ImpactWalker aggregates over
    # whatever is actually in the graph. The user_id param remains for
    # interface compatibility with the frontend call site but is no
    # longer used internally.
    has user_id: str = "demo_user";
    has seed_demo_apps: bool = False;
    # Counts that go back to the client so we can log "seeded X resources"
    # in the dev console on first login. Idempotent re-runs report 0
    # inserted and N skipped.
    has summary: dict = {};

    can run with `Root entry {
        # Resolve the data file relative to the project tree. We try several
        # candidate locations so this works whether jac-scale starts the
        # server from civicmesh/, from the repo root, or via an installed
        # wheel — keeping the seed walker portable across deploy shapes.
        path = "";
        candidates = [
            os.path.join(os.getcwd(), "data", "resources.json"),
            os.path.join(os.getcwd(), "civicmesh", "data", "resources.json"),
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "resources.json")
        ];
        for c in candidates {
            if os.path.exists(c) {
                path = os.path.abspath(c);
                break;
            }
        }
        if not path {
            report {"ok": False, "error": "resources.json not found", "inserted": 0, "skipped": 0};
            return;
        }

        contents = "";
        with open(path, "r") as f {
            contents = f.read();
        }
        payload = json.loads(contents);
        records = list(payload["resources"]);

        inserted = 0;
        skipped = 0;
        for record_raw in records {
            record: Any = record_raw;
            agency = str(record["agency_name"]);
            # Idempotency check: skip if this user's root already owns the
            # ResourceNode. Cheap because the seed catalog is fixed at 40.
            existing = [root --> [?:ResourceNode, agency_name == agency]];
            if existing {
                skipped += 1;
                continue;
            }

            resource = ResourceNode(
                agency_name=agency,
                category=str(record["category"]),
                capacity=str(record["capacity"]),
                languages_supported=list(record["languages_supported"]),
                contact_phone=str(record["contact_phone"]),
                contact_email=str(record["contact_email"]),
                address=str(record["address"]),
                online_url=str(record["online_url"]),
                description=str(record["description"])
            );
            root ++> resource;

            elig_raw = record["eligibility"];
            rule = EligibilityRuleNode(
                rule_id=str(elig_raw["rule_id"]),
                income_limit_annual=int(elig_raw["income_limit_annual"]),
                residency_requirement=str(elig_raw["residency_requirement"]),
                min_family_size=int(elig_raw["min_family_size"]),
                citizenship_required=bool(elig_raw["citizenship_required"]),
                age_min=int(elig_raw["age_min"]),
                age_max=int(elig_raw["age_max"]),
                exceptions=str(elig_raw["exceptions"]),
                criteria_summary=str(elig_raw["criteria_summary"])
            );
            resource +>: governed_by() :+> rule;

            form_raw = record["form"];
            form = FormNode(
                form_id=str(form_raw["form_id"]),
                form_name=str(form_raw["form_name"]),
                url=str(form_raw["url"]),
                required_documents=list(form_raw["required_documents"]),
                deadline_type=str(form_raw["deadline_type"]),
                submission_method=str(form_raw["submission_method"]),
                estimated_minutes=int(form_raw["estimated_minutes"])
            );
            rule +>: requires_form() :+> form;

            inserted += 1;
        }

        # Second pass: stitch leads_to edges between ResourceNodes for the
        # PathfinderWalker. These are curated real-world transitions that
        # produce multi-step escape paths when direct eligibility fails.
        # Each tuple is (from_agency, to_agency, reason, days, difficulty).
        pathfinder_edges: list = [
            # Housing escape chain — names match resources.json exactly so
            # the seed-pass matcher actually resolves them.
            ("Emergency Solutions Grant Shelter Network", "Rapid Re-Housing Program",
             "Emergency shelter intake auto-files a Continuum-of-Care referral; expect rapid re-housing placement within 30 days.",
             30, "easy"),
            ("Rapid Re-Housing Program", "Section 8 Housing Choice Voucher Program",
             "Verified rapid re-housing tenancy moves you up the local Section 8 priority list as a stabilized low-income tenant.",
             120, "moderate"),
            ("Emergency Solutions Grant Shelter Network", "Continuum of Care Permanent Supportive Housing",
             "Shelter-based intake counts as the CoC entry point; long-term supportive housing typically opens within 90 days for verified high-need cases.",
             90, "moderate"),
            ("National Domestic Violence Hotline Shelter Referral", "Emergency Solutions Grant Shelter Network",
             "DV hotline can arrange same-day shelter placement for survivors and their dependents through coordinated entry.",
             1, "easy"),
            ("Salvation Army Transitional Housing", "Section 8 Housing Choice Voucher Program",
             "Twelve-month transitional residency at Salvation Army produces the documented tenancy history Section 8 priority lists weight heavily.",
             365, "moderate"),
            ("Catholic Charities Emergency Rental Assistance", "Section 8 Housing Choice Voucher Program",
             "Catholic Charities case managers routinely escalate ERA recipients into the Section 8 application pipeline.",
             60, "easy"),
            ("HUD-VASH (Veterans Affairs Supportive Housing)", "Section 8 Housing Choice Voucher Program",
             "VASH vouchers are HUD-managed Section 8 with VA case management — converting between them is administrative.",
             45, "easy"),

            # Food escape chain
            ("Feeding America Food Bank Network", "SNAP (Supplemental Nutrition Assistance Program)",
             "Member food banks routinely capture SNAP eligibility data at intake; staff can submit on your behalf with consent.",
             14, "easy"),
            ("SNAP (Supplemental Nutrition Assistance Program)", "WIC (Women, Infants and Children)",
             "Most SNAP-approved households with children under 5 or pregnant members also qualify for WIC; cross-enrollment is automatic in most states.",
             14, "easy"),
            ("Meals on Wheels America", "SNAP (Supplemental Nutrition Assistance Program)",
             "Home-delivered-meal recipients are pre-qualified for expedited SNAP review under elderly/disabled provisions.",
             21, "easy"),
            ("TEFAP (The Emergency Food Assistance Program)", "SNAP (Supplemental Nutrition Assistance Program)",
             "TEFAP distribution sites are SNAP outreach points; staff can complete and submit your application same-day.",
             14, "easy"),
            ("Community Fridge Network", "Feeding America Food Bank Network",
             "Community fridge volunteers maintain warm hand-offs to nearest food bank when sustained food access is needed.",
             1, "easy"),

            # Healthcare escape chain
            ("Federally Qualified Health Center Sliding-Scale Care", "Medicaid",
             "FQHC patient navigators submit Medicaid applications and track them through approval at zero cost.",
             45, "moderate"),
            ("Medicaid", "Federally Qualified Health Center Sliding-Scale Care",
             "Medicaid coverage unlocks the full FQHC sliding-scale clinic network for ongoing primary and specialty care.",
             7, "easy"),
            ("988 Suicide and Crisis Lifeline", "Community Mental Health Center Sliding-Scale Therapy",
             "988 counselors warm-transfer callers to community mental health centers for ongoing care.",
             3, "easy"),
            ("NeedyMeds Prescription Assistance", "Federally Qualified Health Center Sliding-Scale Care",
             "NeedyMeds maintains a national directory of FQHC clinics for users without primary care.",
             7, "easy"),
            ("CHIP (Children's Health Insurance Program)", "Medicaid",
             "CHIP and Medicaid share a single application portal; ineligibility for one auto-routes the other.",
             14, "easy"),

            # Legal escape chain
            ("Legal Services Corporation Civil Legal Aid", "Tenant Rights Hotline (National Housing Law Project)",
             "When LSC programs can't take a tenant case directly, they refer to NHLP-affiliated tenant defender coalitions.",
             7, "moderate"),
            ("ABA Free Legal Answers", "Legal Services Corporation Civil Legal Aid",
             "ABA Free Legal Answers triages cases and refers complex matters to LSC-funded local providers.",
             7, "easy"),
            ("National Domestic Violence Legal Advocacy", "Legal Services Corporation Civil Legal Aid",
             "DV legal advocates connect survivors to LSC for protective orders and custody filings the same week.",
             3, "easy"),
            ("Disability Rights Network Protection and Advocacy", "Legal Services Corporation Civil Legal Aid",
             "Disability rights P&A networks refer non-disability-specific cases to general LSC providers.",
             14, "easy"),

            # Cross-vertical bridges — the magic that makes pathfinding non-obvious
            ("Feeding America Food Bank Network", "Section 8 Housing Choice Voucher Program",
             "Food bank intake captures housing instability data; case managers refer high-risk families to Section 8 priority lists.",
             45, "moderate"),
            ("National Domestic Violence Hotline Shelter Referral", "National Domestic Violence Legal Advocacy",
             "Same-organization warm-handoff: hotline counselor schedules the legal advocate visit while you're still on the call.",
             1, "easy"),
            ("Federally Qualified Health Center Sliding-Scale Care", "SNAP (Supplemental Nutrition Assistance Program)",
             "FQHC social workers screen every patient for food insecurity and submit SNAP applications on their behalf.",
             14, "easy"),
            ("988 Suicide and Crisis Lifeline", "Emergency Solutions Grant Shelter Network",
             "988 counselors maintain shelter-availability tables; can arrange same-night placement for housing-insecure callers.",
             1, "easy"),
            ("Tenant Rights Hotline (National Housing Law Project)", "Catholic Charities Emergency Rental Assistance",
             "Tenant rights advocates refer eviction-defense clients to ERA programs to pay back rent and stop the case.",
             7, "easy")
        ];

        edges_added = 0;
        edges_skipped_missing = 0;
        edges_skipped_existing = 0;
        # Build a name→node lookup once instead of N×2 graph queries per
        # iteration. Also avoids subtle ordering issues with the tuple
        # iteration that were producing "1 added, 25 skipped" reports
        # when the actual graph had no leads_to edges at all.
        all_resources_list = [root --> [?:ResourceNode]];
        name_to_node: dict = {};
        for r in all_resources_list {
            try {
                name_to_node[str(r.agency_name)] = r;
            } except Exception as _ex {}
        }

        for edge_spec in pathfinder_edges {
            from_name = str(edge_spec[0]);
            to_name = str(edge_spec[1]);
            if (from_name not in name_to_node) or (to_name not in name_to_node) {
                edges_skipped_missing += 1;
                continue;
            }
            src_node: Any = name_to_node[from_name];
            tgt_node: Any = name_to_node[to_name];

            # Idempotency: walk outgoing leads_to neighbors and string-
            # compare. Done as a flat loop (not an inline predicate)
            # because earlier predicate-based versions over-matched.
            already_present = False;
            existing_neighbors = [src_node ->:leads_to:-> [?:ResourceNode]];
            for neighbor in existing_neighbors {
                try {
                    if str(neighbor.agency_name) == to_name {
                        already_present = True;
                        break;
                    }
                } except Exception as _ex {}
            }
            if already_present {
                edges_skipped_existing += 1;
                continue;
            }

            src_node +>: leads_to(
                transition_reason=str(edge_spec[2]),
                typical_days=int(edge_spec[3]),
                difficulty=str(edge_spec[4])
            ) :+> tgt_node;
            edges_added += 1;
        }

        # SeedWalker no longer creates mock ApplicationNodes or a hardcoded
        # PersonNode. Per hackathon feedback, the Action Plan / Impact tabs
        # must show data derived from REAL chat turns. The user's first
        # NavigationWalker hit produces the first ApplicationNode; outcome
        # marking and CritiqueWalker SessionInsights flow from there.

        # Migration cleanup. Earlier versions of SeedWalker persisted
        # three placeholder ApplicationNodes (SNAP applied, WIC pending,
        # Catholic Charities denied) on the demo PersonNode. Jac auto-
        # persists everything reachable from root, so they linger even
        # after we removed the seeding logic. Sweep EVERY PersonNode in
        # the graph (not just self.user_id's) for two patterns:
        #   1. application_id contains "::demo::" (the marker my old
        #      seed code used)
        #   2. notes startswith "Demo state:" (belt-and-braces)
        # Matched apps get status="archived" so the MemoryWalker /
        # ImpactWalker filters skip them. Real ApplicationNodes from
        # NavigationWalker have neither marker.
        demo_apps_archived = 0;
        try {
            all_persons = [root --> [?:PersonNode]];
            for pn in all_persons {
                try {
                    pn_apps = [pn ->:applied_to:-> [?:ApplicationNode]];
                    for app in pn_apps {
                        try {
                            aid = str(app.application_id);
                            notes_raw = str(app.notes) if app.notes else "";
                            is_demo = ("::demo::" in aid) or notes_raw.startswith("Demo state");
                            if is_demo and str(app.status) != "archived" {
                                setattr(app, "status", "archived");
                                demo_apps_archived += 1;
                            }
                        } except Exception as _ex {}
                    }
                } except Exception as _ex {}
            }
        } except Exception as _ex {}

        payload_out = {
            "ok": True,
            "inserted": inserted,
            "skipped": skipped,
            "total": len(records),
            "pathfinder_edges_added": edges_added,
            "pathfinder_edges_skipped_missing": edges_skipped_missing,
            "pathfinder_edges_skipped_existing": edges_skipped_existing,
            "pathfinder_edges_total": len(pathfinder_edges),
            "demo_apps_archived": demo_apps_archived
        };
        self.summary = payload_out;
        report payload_out;
    }
}

sem SeedWalker is "Idempotent per-user graph bootstrap. Materializes the 40 ResourceNode/EligibilityRuleNode/FormNode triples from data/resources.json into the caller's root so EligibilityWalker has something to score against. Called once from the frontend after auth — re-runs are no-ops.";
sem SeedWalker.summary is "Mirror of the final {ok, inserted, skipped, total} payload. Spawning walkers can read this via .summary without going through .reports.";
