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
    has max_candidates: int = 6;
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

            # NOTE: byllm 0.6.7 doesn't accept `incl_info` as a regular
            # stub kwarg, so we pass the primitives explicitly and rely
            # on `sem` strings (on every parameter + return field) to
            # ground the model. The graph context is still richer than
            # a hand-written prompt because every `sem` annotation flows
            # into the system instructions byllm builds.
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

            # Outcome-learning weight: blend the LLM's raw match_score with
            # the EligibilityRuleNode's prior_success_rate so the graph
            # learns from real ApplicationNode outcomes over time. With no
            # historical data the prior is 0.5 and the blend resolves to
            # the raw score; as the rule sees real approvals/denials it
            # gradually shifts the rankings. Pure Jac OSP — no PyTorch.
            raw_score = int(result.match_score);
            prior_rate = 0.5;
            attempts = 0;
            try { prior_rate = float(rule.prior_success_rate); } except Exception as _ex {}
            try { attempts = int(rule.prior_attempts); } except Exception as _ex {}
            # Blend weight grows with attempts: at 0 attempts we trust the
            # LLM entirely; at 20+ attempts we let the prior have ~50%
            # influence. Keeps the cold-start demo responsive.
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
