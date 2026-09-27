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
                criteria_summary=str(elig_raw["criteria_summary"]),
                targets=[str(t) for t in list(elig_raw.get("targets", []))]
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
        pathfinder_edges: list = [];
        trans_path = os.path.join(os.path.dirname(path), "transitions.json");
        if os.path.exists(trans_path) {
            with open(trans_path, "r") as tf {
                for t in json.loads(tf.read())["transitions"] {
                    pathfinder_edges.append((str(t["from"]), str(t["to"]), str(t["reason"]), int(t["days"]), str(t["difficulty"])));
                }
            }
        }

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
