"""NavigationWalker — builds the user-facing ActionPlan.

Spawned by EligibilityWalker from the PersonNode. For each eligible
ResourceNode it walks the requires_form edge through the EligibilityRuleNode
to gather document and deadline info. Then it calls generate_action_plan() to
sequence those into an ordered plan, and persists one ApplicationNode per
step via the applied_to edge so returning users see their state.
"""

import datetime;
import from graph.nodes { PersonNode, ResourceNode, EligibilityRuleNode, FormNode, ApplicationNode }
import from graph.edges { governed_by, requires_form, applied_to }
import from llm.stubs {
    NeedProfile,
    ActionPlan,
    ActionStep,
    generate_action_plan
}

walker NavigationWalker {
    has eligible_results: list;
    has possible_results: list;
    has profile: NeedProfile;
    has person_node: PersonNode;
    # Reports emitted via `report` flow upward into the spawning walker's
    # report stream — child walkers see their own `.reports` as empty. We
    # mirror the final payload here so callers can read it after spawn.
    has summary: dict = {};

    can plan with PersonNode entry {
        ts = datetime.datetime.utcnow().isoformat();

        # Step 1: walk Resource -> governed_by -> Rule -> requires_form -> Form
        # for each eligible resource and collect the form + contact metadata.
        all_resources = [root --> [?:ResourceNode]];
        resource_form_data: list = [];
        eligible_names: list = [];

        for result in self.eligible_results {
            name = str(result["resource_name"]);
            eligible_names.append(name);
            for resource in all_resources {
                if str(resource.agency_name) != name {
                    continue;
                }
                rule_nodes = [resource ->:governed_by:-> [?:EligibilityRuleNode]];
                if not rule_nodes {
                    break;
                }
                rule: EligibilityRuleNode = rule_nodes[0];
                form_nodes = [rule ->:requires_form:-> [?:FormNode]];
                if not form_nodes {
                    break;
                }
                form: FormNode = form_nodes[0];
                resource_form_data.append({
                    "agency_name": name,
                    "match_score": int(result["match_score"]),
                    "required_documents": list(form.required_documents),
                    "deadline_type": str(form.deadline_type),
                    "submission_method": str(form.submission_method),
                    "estimated_minutes": int(form.estimated_minutes),
                    "form_url": str(form.url),
                    "contact_phone": str(result["contact_phone"]),
                    "address": str(result["address"]),
                    "online_url": str(result["online_url"])
                });
                break;
            }
        }

        # Step 2: ask the LLM to sequence the eligible resources into a plan.
        action_plan: ActionPlan = generate_action_plan(
            eligible_resources=eligible_names,
            profile=self.profile
        );

        # Step 3: persist one ApplicationNode per planned step via applied_to.
        for step in action_plan.steps {
            agency = str(step.agency_name);
            here +>: applied_to() :+> ApplicationNode(
                application_id=agency + "::" + ts,
                status="pending",
                resource_name=agency,
                applied_at="",
                updated_at=ts,
                denial_reason="",
                next_step_hint="",
                notes=""
            );
        }

        # Step 4: shape the response. We pull each ActionStep back into a dict
        # so downstream JSON serialization works the same as the LLM payload.
        step_dicts: list = [];
        for s in action_plan.steps {
            step_dicts.append({
                "step_number": int(s.step_number),
                "agency_name": str(s.agency_name),
                "action_description": str(s.action_description),
                "documents_needed": list(s.documents_needed),
                "deadline_label": str(s.deadline_label),
                "contact_info": str(s.contact_info),
                "estimated_minutes": int(s.estimated_minutes),
                "online_url": str(s.online_url)
            });
        }

        payload = {
            "action_plan": {
                "summary": str(action_plan.summary),
                "steps": step_dicts
            },
            "resource_form_data": resource_form_data,
            "application_nodes_created": len(action_plan.steps)
        };
        self.summary = payload;
        report payload;
    }
}
