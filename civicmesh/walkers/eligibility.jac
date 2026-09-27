"""EligibilityWalker — explainable scoring over the resource graph.

Spawned on the turn's NeedNode. One traversal collects every
ResourceNode →governed_by→ EligibilityRuleNode →requires_form→ FormNode triple
(the graph IS the knowledge base), then engine/score.jac scores all of them in
closed form: per-criterion reasons, calibrated tiers with abstention, Beta
approval posteriors, counterfactuals, and the single most informative
follow-up question. No LLM on this path.

It then hands off, all deterministic:
  NavigationWalker  — Smith's-rule ordered plan + ApplicationNodes
  PathfinderWalker  — Yen k-shortest expected-cost routes over leads_to
  EscalationWalker  — crisis lines, only when nothing fits or risk is present
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode, FormNode }
import from graph.edges { governed_by, requires_form, eligible_for }
import from engine.score { rank_resources, question_for }
import from engine.compose { span_begin, span_end, compose_reply }
import from walkers.navigation { NavigationWalker }
import from walkers.pathfinder { PathfinderWalker }
import from walkers.escalation { EscalationWalker }

glob CHIPS: dict = {
    "housing": ["What documents do I need for Section 8?", "Is there emergency shelter I can reach tonight?", "Can I get help with a past-due rent bill?"],
    "food": ["Where is the nearest food bank open today?", "How do I apply for SNAP?", "Can my kids get free school meals?"],
    "healthcare": ["How do I apply for Medicaid?", "Is there a sliding-scale clinic near me?", "How can I get cheaper prescriptions?"],
    "legal": ["Can a free lawyer help with my eviction?", "What are my rights as a tenant?", "How do I find free immigration legal help?"]
};

"""Snapshot a node's fields into a plain dict for the pure engine."""
def resource_dict(r: ResourceNode) -> dict {
    return {
        "agency_name": str(r.agency_name), "category": str(r.category), "capacity": str(r.capacity),
        "languages_supported": list(r.languages_supported), "contact_phone": str(r.contact_phone),
        "contact_email": str(r.contact_email), "address": str(r.address),
        "online_url": str(r.online_url), "description": str(r.description)
    };
}

def rule_dict(e: EligibilityRuleNode) -> dict {
    return {
        "rule_id": str(e.rule_id), "income_limit_annual": int(e.income_limit_annual),
        "residency_requirement": str(e.residency_requirement), "min_family_size": int(e.min_family_size),
        "citizenship_required": bool(e.citizenship_required), "age_min": int(e.age_min),
        "age_max": int(e.age_max), "exceptions": str(e.exceptions),
        "criteria_summary": str(e.criteria_summary), "prior_success_rate": float(e.prior_success_rate),
        "prior_attempts": int(e.prior_attempts), "prior_approvals": int(e.prior_approvals),
        "targets": list(getattr(e, "targets", []) or [])
    };
}

def form_dict(f: FormNode) -> dict {
    return {
        "form_id": str(f.form_id), "form_name": str(f.form_name), "url": str(f.url),
        "required_documents": list(f.required_documents), "deadline_type": str(f.deadline_type),
        "submission_method": str(f.submission_method), "estimated_minutes": int(f.estimated_minutes)
    };
}

"""Compact, authoritative fact sheet for the narrator LLM."""
def facts_for(ranking: dict, plan: dict, question: str, profile: dict) -> str {
    lines: list = [];
    lines.append("need: " + str(profile.get("category", "")) + " (" + str(profile.get("urgency", "")) + ")");
    for s in list(ranking.get("ranked", []))[:4] {
        met = [c["detail"] for c in s["criteria"] if c["status"] == "met"][:2];
        lines.append("- " + s["resource_name"] + " | " + s["tier"] + " | " + s["contact_phone"] + " | " + "; ".join(met));
    }
    steps = list(plan.get("steps", []));
    if steps {
        lines.append("first step: " + steps[0]["agency_name"] + " — " + steps[0]["action_description"]);
    }
    if question {
        lines.append("follow-up question: " + question);
    }
    return "\n".join(lines);
}

# Per-visitor catalog snapshot (resource + rule + form dicts). The catalog is
# static except for outcome learning, so MemoryWalker invalidates the entry
# whenever an approval/denial updates a rule's posterior. Saves ~60-90 ms of
# anchor loads per turn on the server.
glob CATALOG_CACHE: dict = {};

"""Drop a visitor's cached catalog (called after outcome updates)."""
def invalidate_catalog(key: str) -> None {
    CATALOG_CACHE.pop(key, None);
}

walker EligibilityWalker {
    has profile: dict;
    has person_node: PersonNode;
    has message: str = "";
    has language: str = "en";
    has trace: dict = {};
    has parent_span: str = "";
    has summary: dict = {};

    can check with NeedNode entry {
        tr = self.trace;
        lang = self.language if self.language in ["en", "es"] else "en";

        cache_key = str(self.person_node.user_id);
        items: list = list(CATALOG_CACHE.get(cache_key, []));
        cached = len(items) > 0;
        sp = span_begin(tr, "graph.traverse resource→rule→form", "INTERNAL", self.parent_span, {"civicmesh.cache_hit": cached});
        if not cached {
            for r in [root --> [?:ResourceNode]] {
                rules = [r ->:governed_by:-> [?:EligibilityRuleNode]];
                if not rules { continue; }
                rule: EligibilityRuleNode = rules[0];
                forms = [rule ->:requires_form:-> [?:FormNode]];
                items.append({"resource": resource_dict(r), "rule": rule_dict(rule), "form": form_dict(forms[0]) if forms else {}});
            }
            if len(items) > 0 { CATALOG_CACHE[cache_key] = items; }
        }
        span_end(tr, sp, {"civicmesh.programs": len(items)});

        sp = span_begin(tr, "EligibilityWalker score", "INTERNAL", self.parent_span, {"gen_ai.agent.name": "EligibilityWalker"});
        ranking = rank_resources(items, self.profile, self.message, 6, lang);
        ask = ranking["ask"];
        if self.profile.get("defaulted_category") {
            # Nothing routed the message: ask what the need is rather than
            # presenting a guess (housing) as if it were understood.
            ask = {"key": "need", "gain": 1.0, "affects": int(ranking["all_count"])};
        }
        question = question_for(str(ask["key"]), lang) if ask["key"] else "";
        span_end(tr, sp, {"civicmesh.scored": ranking["all_count"], "civicmesh.likely": ranking["tiers"]["likely"], "civicmesh.ask": str(ask["key"])});

        ranked = list(ranking["ranked"]);

        # Persist the verdicts: one scored eligible_for edge per top match, so
        # the case's reasoning lives in the graph (the Graph tab queries it).
        sp = span_begin(tr, "graph.write eligible_for", "INTERNAL", self.parent_span);
        rank_of: dict = {};
        for (i, s) in enumerate(ranked) { rank_of[str(s["resource_name"])] = i; }
        written = 0;
        for r in [root --> [?:ResourceNode]] {
            nm = str(r.agency_name);
            if nm in rank_of {
                s = ranked[int(rank_of[nm])];
                here +>: eligible_for(
                    tier=str(s["tier"]), p_eligible=float(s["p_eligible"]), rank=int(rank_of[nm]),
                    benefit_monthly=int(dict(s.get("benefit", {}) or {}).get("monthly", 0))
                ) :+> r;
                written += 1;
            }
        }
        span_end(tr, sp, {"civicmesh.edges": written});

        nav = self.person_node spawn NavigationWalker(
            ranked=ranked, urgency=str(self.profile.get("urgency", "within_weeks")),
            language=lang, trace=tr, parent_span=self.parent_span
        );
        plan: dict = nav.summary;

        p_of: dict = {};
        for s in ranked { p_of[s["resource_name"]] = float(s["p_eligible"]) * float(s["approval"]["mean"]); }
        sources = [s["resource_name"] for s in ranked if s["tier"] in ["likely", "possible"]];
        goals: dict = {};
        for s in ranked {
            if s["capacity"] == "waitlist" or s["tier"] in ["needs_info", "unlikely"] {
                goals[s["resource_name"]] = max(0.3, float(s["p_eligible"]));
            }
        }
        pf = root spawn PathfinderWalker(
            start_category=str(self.profile.get("category", "")),
            sources=sources, goals=goals, p_of=p_of, trace=tr, parent_span=self.parent_span,
            cache_key=str(self.person_node.user_id)
        );
        routes: list = list(pf.summary.get("paths", []));

        flags = list(self.profile.get("flags", []));
        escalation: dict = {};
        credible = ranking["tiers"]["likely"] + ranking["tiers"]["possible"];
        if credible == 0 or "self_harm" in flags or "dv" in flags {
            esc = self.person_node spawn EscalationWalker(
                category=str(self.profile.get("category", "")), flags=flags,
                language=lang, ranked=ranked, trace=tr, parent_span=self.parent_span
            );
            escalation = esc.summary;
        }

        reply = compose_reply(lang, self.profile, ranking, plan, routes, question);
        chips = list(CHIPS.get(str(self.profile.get("category", "")), CHIPS["housing"]));
        self.summary = {
            "reply": reply,
            "question": {"key": str(ask["key"]), "text": question, "affects": int(ask["affects"]), "gain": float(ask["gain"])},
            "matches": ranked,
            "tiers": ranking["tiers"],
            "near_misses": ranking["near_misses"],
            "plan": plan,
            "routes": routes,
            "escalation": escalation,
            "chips": chips,
            "facts": facts_for(ranking, plan, question, self.profile)
        };
    }
}

sem EligibilityWalker is "Scores every program in the graph against the profile with the deterministic engine, then spawns Navigation, Pathfinder and (if needed) Escalation.";
