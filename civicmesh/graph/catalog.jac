"""The program catalog: one shared copy in memory, not one per visitor.

Every visitor used to get 74 programs, 74 rules, 74 forms and all the edges
between them written to the database: about 400 records and 410 KB before they
typed a word (blind audit F24, F26). The catalog is the same for everyone, so
it's read once from data/. A program becomes a node in a visitor's graph only
when something personal has to point at it: a scored verdict, or an outcome
they recorded. ForgetWalker deletes those copies, since which programs a person
matched says something about them.
"""

import json;
import os;
import sys;
import types;

import from graph.nodes { ResourceNode, EligibilityRuleNode, FormNode }
import from graph.edges { governed_by, requires_form }

glob SHARED: dict = {};

def _data_file(name: str) -> str {
    here = os.path.dirname(os.path.abspath(__file__));
    for c in [os.path.join(os.getcwd(), "data", name), os.path.join(os.getcwd(), "civicmesh", "data", name), os.path.join(here, "..", "data", name)] {
        if os.path.exists(c) { return os.path.abspath(c); }
    }
    return "";
}

def _load -> dict {
    if SHARED { return SHARED; }
    items: list = [];
    records: dict = {};
    edges: list = [];
    try {
        with open(_data_file("resources.json"), encoding="utf-8") as f {
            for r in json.load(f)["resources"] {
                resource = {k: v for (k, v) in r.items() if k not in ["eligibility", "form"]};
                rule = dict(r["eligibility"]);
                rule.setdefault("prior_success_rate", 0.5);
                rule.setdefault("prior_attempts", 0);
                rule.setdefault("prior_approvals", 0);
                rule.setdefault("targets", []);
                item = {"resource": resource, "rule": rule, "form": dict(r["form"])};
                items.append(item);
                records[str(r["agency_name"])] = item;
            }
        }
        trans = _data_file("transitions.json");
        if trans {
            with open(trans, encoding="utf-8") as f {
                for t in json.load(f)["transitions"] {
                    if str(t["from"]) in records and str(t["to"]) in records {
                        edges.append({"from": str(t["from"]), "to": str(t["to"]), "reason": str(t["reason"]), "days": int(t["days"]), "difficulty": str(t["difficulty"])});
                    }
                }
            }
        }
    } except Exception as ex {
        # Crisis lines still answer without a catalog, but nobody should have
        # to guess why every answer came back empty (blind audit F26).
        print("CIVICMESH ERROR: program catalog not loaded: " + type(ex).__name__, file=sys.stderr, flush=True);
        return {"items": [], "records": {}, "edges": []};
    }
    SHARED["items"] = items;
    SHARED["records"] = records;
    SHARED["edges"] = edges;
    return SHARED;
}

"""Every program as {resource, rule, form}, in catalog order. Read-only."""
def shared_items -> list { return list(_load()["items"]); }

"""Program as attributes, the way code reads a node."""
def shared_resources -> list { return [types.SimpleNamespace(**i["resource"]) for i in _load()["items"]]; }

def shared_resource(name: str) -> Any {
    item = _load()["records"].get(name);
    return types.SimpleNamespace(**item["resource"]) if item else None;
}

"""leads_to transitions: {from, to, reason, days, difficulty}."""
def shared_edges -> list { return list(_load()["edges"]); }

"""The catalog with one visitor's recorded outcomes laid over it."""
def visitor_items(home: Any) -> list {
    known: dict = {};
    for r in [home --> [?:ResourceNode]] {
        for rule in [r ->:governed_by:-> [?:EligibilityRuleNode]] {
            if int(rule.prior_attempts) > 0 { known[str(r.agency_name)] = rule; }
        }
    }
    items = shared_items();
    if not known { return items; }
    out: list = [];
    for it in items {
        rule = known.get(str(it["resource"]["agency_name"]));
        if rule {
            r2 = dict(it["rule"]);
            r2["prior_success_rate"] = float(rule.prior_success_rate);
            r2["prior_attempts"] = int(rule.prior_attempts);
            r2["prior_approvals"] = int(rule.prior_approvals);
            it = {"resource": it["resource"], "rule": r2, "form": it["form"]};
        }
        out.append(it);
    }
    return out;
}

"""This visitor's node for a program, created on first need. None if the name isn't in the catalog."""
def ensure_resource(home: Any, name: str) -> Any {
    found = [home --> [?:ResourceNode, agency_name == name]];
    if found { return found[0]; }
    item = _load()["records"].get(name);
    if not item { return None; }
    res = item["resource"];
    made = ResourceNode(
        agency_name=name, category=str(res["category"]), capacity=str(res["capacity"]),
        languages_supported=list(res["languages_supported"]), contact_phone=str(res["contact_phone"]),
        contact_email=str(res["contact_email"]), address=str(res["address"]),
        online_url=str(res["online_url"]), description=str(res["description"])
    );
    home ++> made;
    r = item["rule"];
    rule = EligibilityRuleNode(
        rule_id=str(r["rule_id"]), income_limit_annual=int(r["income_limit_annual"]),
        residency_requirement=str(r["residency_requirement"]), min_family_size=int(r["min_family_size"]),
        citizenship_required=bool(r["citizenship_required"]), age_min=int(r["age_min"]), age_max=int(r["age_max"]),
        exceptions=str(r["exceptions"]), criteria_summary=str(r["criteria_summary"]),
        targets=[str(t) for t in list(r.get("targets", []))]
    );
    made +>: governed_by() :+> rule;
    f = item["form"];
    rule +>: requires_form() :+> FormNode(
        form_id=str(f["form_id"]), form_name=str(f["form_name"]), url=str(f["url"]),
        required_documents=list(f["required_documents"]), deadline_type=str(f["deadline_type"]),
        submission_method=str(f["submission_method"]), estimated_minutes=int(f["estimated_minutes"])
    );
    return made;
}
