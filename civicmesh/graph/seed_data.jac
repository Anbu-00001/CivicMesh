"""Idempotent seed loader for CivicMesh.

Reads data/resources.json and materializes ResourceNode + EligibilityRuleNode
+ FormNode triples into the graph rooted at `root`. Before inserting any
ResourceNode the loader walks root, filters by agency_name, and only spawns
when the result set is empty - so re-running this script never produces
duplicates.

Run: `jac run graph/seed_data.jac`
"""

import json;
import os;

import from graph.nodes { ResourceNode, EligibilityRuleNode, FormNode }
import from graph.edges { governed_by, requires_form }

def _resolve_data_path -> str {
    candidates = [
        os.path.join(os.getcwd(), "data", "resources.json"),
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "resources.json"),
    ];
    for path in candidates {
        if os.path.exists(path) {
            return os.path.abspath(path);
        }
    }
    raise FileNotFoundError("Could not locate data/resources.json from cwd or script directory.");
}

def _load_resources -> list {
    path = _resolve_data_path();
    contents = "";
    with open(path, "r") as f {
        contents = f.read();
    }
    payload = json.loads(contents);
    return list(payload["resources"]);
}

def _resource_exists(agency: str) -> bool {
    # Idempotency check: graph traversal from root, filtered by agency_name.
    # When the scale plugin is active and MongoDB is running, this becomes a
    # constant-time lookup; in local `jac run` mode it walks the in-memory graph.
    matches = [root --> [?:ResourceNode, agency_name == agency]];
    return len(matches) > 0;
}

def _seed_one(record: any) -> bool {
    agency = str(record["agency_name"]);
    if _resource_exists(agency) {
        return False;
    }

    resource = ResourceNode(
        agency_name=agency,
        category=record["category"],
        capacity=record["capacity"],
        languages_supported=record["languages_supported"],
        contact_phone=record["contact_phone"],
        contact_email=record["contact_email"],
        address=record["address"],
        online_url=record["online_url"],
        description=record["description"]
    );
    root ++> resource;

    elig_raw = record["eligibility"];
    rule = EligibilityRuleNode(
        rule_id=elig_raw["rule_id"],
        income_limit_annual=elig_raw["income_limit_annual"],
        residency_requirement=elig_raw["residency_requirement"],
        min_family_size=elig_raw["min_family_size"],
        citizenship_required=elig_raw["citizenship_required"],
        age_min=elig_raw["age_min"],
        age_max=elig_raw["age_max"],
        exceptions=elig_raw["exceptions"],
        criteria_summary=elig_raw["criteria_summary"]
    );
    resource +>: governed_by() :+> rule;

    form_raw = record["form"];
    form = FormNode(
        form_id=form_raw["form_id"],
        form_name=form_raw["form_name"],
        url=form_raw["url"],
        required_documents=form_raw["required_documents"],
        deadline_type=form_raw["deadline_type"],
        submission_method=form_raw["submission_method"],
        estimated_minutes=form_raw["estimated_minutes"]
    );
    rule +>: requires_form() :+> form;

    return True;
}

def seed -> dict {
    inserted = 0;
    skipped = 0;
    records = _load_resources();
    for record in records {
        if _seed_one(record) {
            inserted += 1;
        } else {
            skipped += 1;
        }
    }
    return {"inserted": inserted, "skipped": skipped, "total": len(records)};
}

with entry {
    result = seed();
    print(f"Seeded {result['inserted']} resources, skipped {result['skipped']} duplicates (total in file: {result['total']}).");
}
