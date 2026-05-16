"""EligibilityWalker — joins NeedNode.category to ResourceNodes, scores each.

Spawned by IntakeWalker from a NeedNode. For every ResourceNode whose category
matches the profile, it walks the governed_by edge to the EligibilityRuleNode
and asks check_eligibility() for a per-resource match score. Results are
ranked, then we either escalate (nothing viable) or hand off to NavigationWalker.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode }
import from graph.edges { governed_by }
import from llm.stubs {
    NeedProfile,
    EligibilityResult,
    EscalationContext,
    check_eligibility
}
import from walkers.navigation { NavigationWalker }
import from walkers.escalation { EscalationWalker }

walker EligibilityWalker {
    has profile: NeedProfile;
    has person_node: PersonNode;
    has results: list = [];
    # Hard cap on how many ResourceNodes we feed to check_eligibility().
    # Each candidate is one LLM call, so a low default keeps us inside
    # Gemini's free-tier rate window during integration tests. Production
    # callers can raise this when they pass the walker into spawn().
    has max_candidates: int = 3;
    # Mirror of the final report so the spawning walker can read it after
    # spawn — `report` payloads flow only into the outermost walker's stream.
    has summary: dict = {};

    can check with NeedNode entry {
        # Step 1: find candidate ResourceNodes that match this need's category
        need_category = str(self.profile.category);
        all_in_category = [root --> [?:ResourceNode, category == need_category]];
        # Prefer open capacity, then waitlist; closed resources sink to the bottom
        # so they only get a slot if nothing else is available.
        ranked: list = [];
        for r in all_in_category {
            cap = str(r.capacity);
            if cap == "open" {
                ranked.append(r);
            }
        }
        for r in all_in_category {
            cap = str(r.capacity);
            if cap == "waitlist" {
                ranked.append(r);
            }
        }
        for r in all_in_category {
            cap = str(r.capacity);
            if cap != "open" and cap != "waitlist" {
                ranked.append(r);
            }
        }
        candidates = ranked[:self.max_candidates];

        # Step 2: score each candidate by destructuring its EligibilityRuleNode
        for resource in candidates {
            rule_nodes = [resource ->:governed_by:-> [?:EligibilityRuleNode]];
            if not rule_nodes {
                continue;
            }
            rule: EligibilityRuleNode = rule_nodes[0];

            result: EligibilityResult = check_eligibility(
                profile=self.profile,
                criteria_summary=str(rule.criteria_summary),
                income_limit=int(rule.income_limit_annual),
                citizenship_required=bool(rule.citizenship_required),
                residency_req=str(rule.residency_requirement),
                age_min=int(rule.age_min),
                age_max=int(rule.age_max),
                exceptions=str(rule.exceptions)
            );

            self.results.append({
                "resource_name": str(resource.agency_name),
                "match_score": int(result.match_score),
                "is_eligible": bool(result.is_eligible),
                "matched_criteria": list(result.matched_criteria),
                "missing_criteria": list(result.missing_criteria),
                "contact_phone": str(resource.contact_phone),
                "contact_email": str(resource.contact_email),
                "address": str(resource.address),
                "online_url": str(resource.online_url),
                "description": str(resource.description)
            });
        }

        # Step 3: rank by match_score descending, split into tiers
        self.results.sort(key=lambda r : -int(r["match_score"]));
        eligible = [r for r in self.results if int(r["match_score"]) >= 40];
        possible = [r for r in self.results if 20 <= int(r["match_score"]) < 40];

        # Step 4: dead end -> escalate; otherwise plan a path forward
        if not eligible and not possible {
            denial_reasons: list = [];
            for r in self.results {
                missing = list(r["missing_criteria"]);
                if missing {
                    denial_reasons.append(", ".join([str(m) for m in missing]));
                }
            }
            esc_context = EscalationContext(
                trigger_reason="zero_eligible_resources",
                profile=self.profile,
                denial_reasons=denial_reasons,
                urgency_level=str(self.profile.urgency)
            );
            esc_walker = self.person_node spawn EscalationWalker(
                context=esc_context,
                person_node=self.person_node
            );
            esc_payload: dict = esc_walker.summary;
            payload = {"escalated": True, "escalation": esc_payload};
            self.summary = payload;
            report payload;
            disengage;
        }

        nav_walker = self.person_node spawn NavigationWalker(
            eligible_results=eligible,
            possible_results=possible,
            profile=self.profile,
            person_node=self.person_node
        );
        nav_payload: dict = nav_walker.summary;

        top_matches: list = [];
        for r in eligible[:5] {
            top_matches.append({
                "resource": str(r["resource_name"]),
                "score": int(r["match_score"])
            });
        }

        payload = {
            "escalated": False,
            "eligible_count": len(eligible),
            "possible_count": len(possible),
            "top_matches": top_matches,
            "action_plan": nav_payload
        };
        self.summary = payload;
        report payload;
    }
}
