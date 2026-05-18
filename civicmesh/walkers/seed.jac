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

import from graph.nodes { ResourceNode, EligibilityRuleNode, FormNode }
import from graph.edges { governed_by, requires_form }


walker SeedWalker {
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

        payload_out = {
            "ok": True,
            "inserted": inserted,
            "skipped": skipped,
            "total": len(records)
        };
        self.summary = payload_out;
        report payload_out;
    }
}

sem SeedWalker is "Idempotent per-user graph bootstrap. Materializes the 40 ResourceNode/EligibilityRuleNode/FormNode triples from data/resources.json into the caller's root so EligibilityWalker has something to score against. Called once from the frontend after auth — re-runs are no-ops.";
sem SeedWalker.summary is "Mirror of the final {ok, inserted, skipped, total} payload. Spawning walkers can read this via .summary without going through .reports.";
