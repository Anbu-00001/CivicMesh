"""EligibilityWalker — joins NeedNode.category to ResourceNodes, scores each.

Spawned by IntakeWalker from a NeedNode. For every ResourceNode whose category
matches the profile, it walks the governed_by edge to the EligibilityRuleNode
and asks check_eligibility() for a per-resource match score. Results are
ranked, then we either escalate (nothing viable) or hand off to NavigationWalker.

DEMO_MODE / LLM resilience: when the env var CIVICMESH_DEMO_MODE=1 is set
(or when check_eligibility raises — timeout, 429, network error), the
walker skips the LLM and synthesizes a deterministic per-candidate score
from the EligibilityRuleNode's prior_success_rate (Laplace-smoothed) plus
a category-match bonus. This means the chat ALWAYS completes within ~2
seconds, even if NVIDIA NIM is dead. Set CIVICMESH_DEMO_MODE=1 in the HF
Space secrets for launch-day reliability.
"""

import os;
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
import from walkers.pathfinder { PathfinderWalker }

walker EligibilityWalker {
    has profile: NeedProfile;
    has person_node: PersonNode;
    has results: list = [];
    # Hard cap on how many ResourceNodes we feed to check_eligibility().
    # Each candidate is one LLM call. 6 is the cost-disciplined demo value
    # — it covers each category bucket's top open-capacity entries while
    # keeping a single chat turn under ~10 total LLM calls (intake +
    # eligibility×6 + navigation + translation), well inside NVIDIA NIM's
    # free-tier 40 RPM rate window. The PathfinderWalker fallback covers
    # the edge case where 6 candidates all score under threshold by
    # walking the leads_to graph to find multi-hop escape paths instead
    # of issuing more expensive LLM scoring calls.
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

        # DEMO_MODE — skip every LLM call in the scoring loop and use a
        # deterministic score based on the EligibilityRuleNode's
        # prior_success_rate plus a capacity bonus. Always completes in
        # under 2 seconds even when NVIDIA NIM is unreachable. Set
        # CIVICMESH_DEMO_MODE=1 in HF Space secrets for launch reliability.
        demo_mode = False;
        try {
            demo_mode = (str(os.environ.get("CIVICMESH_DEMO_MODE", "0")) == "1");
        } except Exception as _ex {}

        # Step 2: score each candidate by destructuring its EligibilityRuleNode
        for resource in candidates {
            rule_nodes = [resource ->:governed_by:-> [?:EligibilityRuleNode]];
            if not rule_nodes {
                # Resource exists but its EligibilityRuleNode is missing
                # (schema drift, partial seed, etc.). Skip the LLM call but
                # still surface the resource with a neutral score so
                # NavigationWalker is reachable instead of escalation. The
                # user gets the real phone number from the seeded resource;
                # documentation gaps are flagged so they know to confirm.
                self.results.append({
                    "resource_name": str(resource.agency_name),
                    "match_score": 20,
                    "raw_llm_score": 0,
                    "prior_success_rate": 0.5,
                    "prior_attempts": 0,
                    "is_eligible": False,
                    "matched_criteria": [],
                    "missing_criteria": ["Eligibility not scored — call the agency to confirm"],
                    "contact_phone": str(resource.contact_phone),
                    "contact_email": str(resource.contact_email),
                    "address": str(resource.address),
                    "online_url": str(resource.online_url),
                    "description": str(resource.description)
                });
                continue;
            }
            rule: EligibilityRuleNode = rule_nodes[0];

            # Read the prior up front — needed for both LLM and deterministic paths.
            prior_rate = 0.5;
            attempts = 0;
            try { prior_rate = float(rule.prior_success_rate); } except Exception as _ex {}
            try { attempts = int(rule.prior_attempts); } except Exception as _ex {}

            raw_score = 0;
            is_elig_flag = False;
            matched: list = [];
            missing: list = [];
            llm_used = False;

            # Demo mode OR the LLM call fails / times out → synthesize a
            # deterministic score. The walker MUST complete even if NIM
            # is unreachable. Score formula: prior_rate × 70 (so a
            # neutral 0.5 prior maps to 35) + capacity bonus of +20 for
            # "open" and +10 for "waitlist". Net result: open-capacity
            # programs land in the eligible tier (>= 15), waitlist in
            # possible, closed in rescue.
            if demo_mode {
                cap_bonus = 0;
                cap_str = str(resource.capacity);
                if cap_str == "open" { cap_bonus = 20; }
                elif cap_str == "waitlist" { cap_bonus = 10; }
                raw_score = int(prior_rate * 70.0) + cap_bonus;
                is_elig_flag = (raw_score >= 30);
                matched = ["Category match (" + str(resource.category) + ")"];
                missing = ["Confirm full eligibility when you call"];
            } else {
                try {
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
                    raw_score = int(result.match_score);
                    is_elig_flag = bool(result.is_eligible);
                    matched = list(result.matched_criteria);
                    missing = list(result.missing_criteria);
                    llm_used = True;
                } except Exception as _ex {
                    # LLM timeout / 429 / connection error. Fall back to
                    # the deterministic score so the walker still produces
                    # a useful result instead of hanging.
                    cap_bonus = 0;
                    cap_str = str(resource.capacity);
                    if cap_str == "open" { cap_bonus = 20; }
                    elif cap_str == "waitlist" { cap_bonus = 10; }
                    raw_score = int(prior_rate * 70.0) + cap_bonus;
                    is_elig_flag = (raw_score >= 30);
                    matched = ["Category match (" + str(resource.category) + ")"];
                    missing = ["LLM scoring unavailable — call the agency to confirm"];
                }
            }

            # Blend with Outcome-Learning prior. Same formula as before but
            # applied uniformly to LLM and deterministic scores.
            blend = float(attempts) / (float(attempts) + 20.0);
            adjusted_score = int(
                (1.0 - blend) * float(raw_score) + blend * prior_rate * 100.0
            );

            self.results.append({
                "resource_name": str(resource.agency_name),
                "match_score": adjusted_score,
                "raw_llm_score": raw_score,
                "prior_success_rate": prior_rate,
                "prior_attempts": attempts,
                "is_eligible": is_elig_flag,
                "matched_criteria": matched,
                "missing_criteria": missing,
                "contact_phone": str(resource.contact_phone),
                "contact_email": str(resource.contact_email),
                "address": str(resource.address),
                "online_url": str(resource.online_url),
                "description": str(resource.description)
            });
        }

        # Step 3: rank by match_score descending, split into tiers.
        # Thresholds tuned permissively because LLM scoring on civic-aid
        # eligibility is genuinely noisy and conservative — Section 8
        # often scores 10-25 even for a textbook candidate. Eligible
        # >= 15, Possible 5..15. If both tiers are empty BUT results
        # exist (i.e. the LLM produced *something*), we promote the top
        # 3 scored resources into a "rescue tier" treated as Possible so
        # NavigationWalker still gets called and the user sees an
        # actionable plan instead of dropping straight to crisis.
        self.results.sort(key=lambda r : -int(r["match_score"]));
        eligible = [r for r in self.results if int(r["match_score"]) >= 15];
        possible = [r for r in self.results if 5 <= int(r["match_score"]) < 15];
        if len(eligible) == 0 and len(possible) == 0 and len(self.results) > 0 {
            # Rescue tier: take whatever the LLM ranked, regardless of
            # threshold. Better to surface "here are the closest matches,
            # apply with documentation gaps" than to escalate when real
            # options exist in the graph.
            possible = list(self.results[:3]);
        }
        # Last-resort rescue: if EVEN self.results is empty (e.g. zero
        # candidates had governed_by edges, or the LLM returned malformed
        # output on every scoring call), synthesize a results list directly
        # from the category's open-capacity resources. We give them a
        # default score of 25 so NavigationWalker treats them as possible
        # matches. Concrete phone numbers in the user's hand >
        # generic escalation language any day.
        if len(eligible) == 0 and len(possible) == 0 and len(self.results) == 0 {
            synth: list = [];
            for r in candidates[:3] {
                synth.append({
                    "resource_name": str(r.agency_name),
                    "match_score": 25,
                    "raw_llm_score": 0,
                    "prior_success_rate": 0.5,
                    "prior_attempts": 0,
                    "is_eligible": False,
                    "matched_criteria": [],
                    "missing_criteria": ["Eligibility could not be scored — call the agency to confirm"],
                    "contact_phone": str(r.contact_phone),
                    "contact_email": str(r.contact_email),
                    "address": str(r.address),
                    "online_url": str(r.online_url),
                    "description": str(r.description)
                });
            }
            if synth {
                possible = synth;
                self.results = synth;
            }
        }

        # Step 4: dead-end handling. BEFORE escalating to a crisis message,
        # try PathfinderWalker — multi-hop BFS over the `leads_to` edge
        # type looking for a 2-3 step escape route. The seed_resource_names
        # we pass are the borderline near-misses the LLM already scored;
        # they become preferred BFS roots because they're the closest
        # almost-fits.
        # NOTE: `not eligible` compiles to `![]` in JS which is always
        # False because arrays are truthy. Use the explicit length check
        # so the dead-end branch (pathfinder/escalation) actually fires
        # when both tiers are empty.
        if len(eligible) == 0 and len(possible) == 0 {
            denial_reasons: list = [];
            for r in self.results {
                missing = list(r["missing_criteria"]);
                if missing {
                    denial_reasons.append(", ".join([str(m) for m in missing]));
                }
            }

            # Take up to 4 near-misses as Pathfinder seeds. results was
            # already sorted descending by match_score, so [:4] are the
            # closest-fit programs the LLM evaluated.
            near_miss_names: list[str] = [];
            for r in self.results[:4] {
                near_miss_names.append(str(r["resource_name"]));
            }
            pf_walker = root spawn PathfinderWalker(
                start_category=str(self.profile.category),
                max_hops=3,
                max_paths=3,
                seed_resource_names=near_miss_names
            );
            pf_payload: dict = pf_walker.summary;
            pf_path_count = int(pf_payload["path_count"]) if pf_payload and pf_payload["path_count"] else 0;

            # Only escalate if Pathfinder ALSO found nothing. Otherwise
            # the chat surfaces the discovered escape paths and skips the
            # crisis message — a much better user experience.
            if pf_path_count == 0 {
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

            # Pathfinder hit — surface escape paths as the agent's reply.
            payload = {
                "escalated": False,
                "pathfinder_used": True,
                "eligible_count": 0,
                "possible_count": 0,
                "top_matches": [],
                "pathfinder": pf_payload
            };
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

sem EligibilityWalker is "Joins a NeedNode's category to ResourceNodes, scores each via check_eligibility(), and either escalates (no viable match) or hands off to NavigationWalker. Spawned by IntakeWalker on the NeedNode.";
sem EligibilityWalker.profile is "The user's NeedProfile snapshot. Passed into every check_eligibility() call as the demographic context to score against.";
sem EligibilityWalker.person_node is "Root PersonNode of the session subgraph. Used as the spawn target for NavigationWalker and EscalationWalker.";
sem EligibilityWalker.results is "Accumulator of per-resource EligibilityResult dicts. Sorted by match_score descending before tier-splitting.";
sem EligibilityWalker.max_candidates is "Hard cap on how many ResourceNodes are fed into check_eligibility(). Each candidate is one LLM call, so a low default protects the free-tier rate window.";
sem EligibilityWalker.summary is "Mirror of the walker's final report payload. Lets the spawning walker read the result after spawn returns; .reports only flows into the outermost walker's stream.";
