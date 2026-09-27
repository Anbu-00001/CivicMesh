"""IntakeWalker — entry point and orchestrator for one chat turn.

Math-first pipeline, traced end to end:

  1. intake.parse     deterministic EN/ES parser (engine/parse.jac), < 1 ms,
                      merged with the profile carried from earlier turns
  2. gen_ai.chat      ONLY if the parser can't route the message: one typed
                      LLM call (understand_message), 6 s budget, then fall back
  3. graph.write      find-or-create PersonNode, attach NeedNode (has_need)
  4. EligibilityWalker → Navigation / Pathfinder / Escalation (all deterministic)
  5. CritiqueWalker   Reflexion write-back (SessionInsight on reflected_on)

The report carries the answer, the explainable match cards, the plan, the
escape routes, and an OpenTelemetry-shaped span list for the latency
waterfall. The client then calls NarrateWalker (the one LLM call) in the
background to localize and warm up the wording.
"""

import datetime;
import from graph.nodes { PersonNode, NeedNode }
import from graph.edges { has_need }
import from llm.stubs { understand_message, pool_model_names }
import from engine.parse { parse_intake }
import from engine.compose { merge_profiles, new_trace, span_begin, span_end, export_spans }
import from walkers.eligibility { EligibilityWalker }
import from walkers.critique { CritiqueWalker }

glob CATEGORIES: list = ["housing", "food", "healthcare", "legal"];

walker IntakeWalker {
    has conversation: str;
    has user_id: str;
    # Profile from the previous turn (client-held), so an answer to the
    # agent's follow-up question refines the same case.
    has prior: dict = {};
    # Key of the follow-up question this message answers (yes/no answers).
    has answering: str = "";
    has chain_events: list = [];

    can intake with `Root entry {
        tr = new_trace();
        root_span = span_begin(tr, "invoke_agent CivicMesh", "SERVER", "", {"gen_ai.operation.name": "invoke_agent", "gen_ai.agent.name": "CivicMesh"});
        rid = root_span["span_id"];
        ts = datetime.datetime.utcnow().isoformat();
        text = str(self.conversation);

        sp = span_begin(tr, "intake.parse", "INTERNAL", rid);
        parsed = parse_intake(text);
        profile = merge_profiles(dict(self.prior) if self.prior else {}, parsed, text, str(self.answering));
        span_end(tr, sp, {"civicmesh.category": profile["category"], "civicmesh.category_conf": profile["category_conf"], "civicmesh.language": profile["language"], "civicmesh.fields_known": profile["completeness"], "civicmesh.evidence_spans": len(parsed["evidence"])});

        llm_sync = False;
        llm_reason = str(profile.get("llm_reason", ""));
        llm_error = "";
        if profile.get("needs_llm", False) {
            llm_sync = True;
            models = pool_model_names();
            sp = span_begin(tr, "chat understand_message", "CLIENT", rid, {"gen_ai.operation.name": "chat", "gen_ai.request.model": models[0] if models else "", "gen_ai.system": "litellm", "civicmesh.reason": llm_reason});
            try {
                u = understand_message(message=text);
                cat = str(u.category).strip().lower();
                if cat in CATEGORIES {
                    profile["category"] = cat;
                    profile["category_conf"] = 0.7;
                }
                lang = str(u.language).strip().lower()[:2];
                if lang and not profile.get("language") { profile["language"] = lang; }
                if int(profile.get("income_annual", -1)) < 0 and int(u.monthly_income) >= 0 { profile["income_annual"] = int(u.monthly_income) * 12; }
                if int(profile.get("household_size", 0)) <= 0 and int(u.household_size) > 0 { profile["household_size"] = int(u.household_size); }
                if int(profile.get("age", 0)) <= 0 and int(u.age) > 0 { profile["age"] = int(u.age); }
                if not profile.get("state") and len(str(u.state)) == 2 { profile["state"] = str(u.state).upper(); }
                if not profile.get("citizenship") and str(u.citizenship) in ["citizen", "eligible_immigrant", "non_citizen"] { profile["citizenship"] = str(u.citizenship); }
                if str(u.urgency) == "immediate" { profile["urgency"] = "immediate"; }
                profile["llm_summary"] = str(u.english_summary);
                span_end(tr, sp, {"civicmesh.category": profile["category"]});
            } except Exception as ex {
                llm_error = str(ex)[:160];
                span_end(tr, sp, {"error.type": type(ex).__name__}, "ERROR");
            }
        }
        lang_out = str(profile.get("language", "") or "en");
        if not profile.get("category") {
            # Still nothing to route on: default to the broadest safety net
            # and let the follow-up question narrow it down.
            profile["category"] = "food" if ("hungry" in text.lower()) else "housing";
            profile["category_conf"] = 0.1;
            profile["defaulted_category"] = True;
        }

        sp = span_begin(tr, "graph.write person+need", "INTERNAL", rid);
        existing = [root --> [?:PersonNode, user_id == self.user_id]];
        person_node: PersonNode;
        if existing {
            person_node = existing[0];
        } else {
            created = root ++> PersonNode(user_id=self.user_id, language=lang_out, created_at=ts);
            person_node = created[0];
        }
        setattr(person_node, "language", lang_out);
        if int(profile.get("household_size", 0)) > 0 { setattr(person_node, "family_size", int(profile["household_size"])); }
        if profile.get("zip") { setattr(person_node, "location_zip", str(profile["zip"])); }
        if int(profile.get("income_annual", -1)) >= 0 { setattr(person_node, "income_bracket", str(profile["income_annual"])); }
        attached = person_node +>: has_need() :+> NeedNode(
            category=str(profile["category"]),
            urgency=str(profile["urgency"]),
            details=text[:500],
            created_at=ts
        );
        need_node: NeedNode = attached[0];
        span_end(tr, sp);

        elig = need_node spawn EligibilityWalker(
            profile=profile,
            person_node=person_node,
            message=str(profile.get("case_text", text)),
            language=lang_out,
            trace=tr,
            parent_span=rid
        );
        result: dict = elig.summary;

        sp = span_begin(tr, "reflexion.critique", "INTERNAL", rid);
        try {
            ranked = list(result.get("matches", []));
            critique = person_node spawn CritiqueWalker(
                user_id=self.user_id,
                walker_events=list(self.chain_events),
                user_prompt=text,
                eligible_count=int(result.get("tiers", {}).get("likely", 0)),
                escalated=bool(result.get("escalation")),
                pathfinder_used=len(list(result.get("routes", []))) > 0,
                navigation_used=len(list(result.get("plan", {}).get("steps", []))) > 0,
                need_category=str(profile["category"]),
                need_urgency=str(profile["urgency"]),
                top_resource=str(ranked[0]["resource_name"]) if ranked else ""
            );
            span_end(tr, sp);
        } except Exception as ex {
            span_end(tr, sp, {"error.type": type(ex).__name__}, "ERROR");
        }

        span_end(tr, root_span, {"civicmesh.llm_calls_sync": 1 if llm_sync else 0});
        spans = export_spans(tr);

        public_profile = {k: v for (k, v) in profile.items() if k not in ["evidence", "category_scores"]};
        # Sorted, non-overlapping evidence spans so the client can highlight
        # the user's own words inline in a single linear pass.
        ev_sorted = sorted(list(parsed["evidence"]), key=lambda e: dict : (int(e["start"]), -int(e["end"])));
        highlights: list = [];
        last_end = -1;
        for e in ev_sorted {
            if int(e["start"]) >= last_end {
                highlights.append(e);
                last_end = int(e["end"]);
            }
        }
        report {
            "version": 2,
            "language": lang_out,
            "profile": public_profile,
            "evidence": highlights,
            "category_scores": parsed["category_scores"],
            "reply": result.get("reply", ""),
            "question": result.get("question", {}),
            "matches": result.get("matches", []),
            "tiers": result.get("tiers", {}),
            "near_misses": result.get("near_misses", []),
            "plan": result.get("plan", {}),
            "routes": result.get("routes", []),
            "escalation": result.get("escalation", {}),
            "chips": result.get("chips", []),
            "facts": result.get("facts", ""),
            "llm": {"sync_used": llm_sync, "reason": llm_reason, "error": llm_error, "models": pool_model_names(), "narrate": not llm_sync},
            "trace": {"trace_id": tr["trace_id"], "total_ms": root_span.get("duration_ms", 0.0), "spans": spans}
        };
    }
}

sem IntakeWalker is "Entry walker for every chat turn: deterministic parse (plus one LLM call only if the message can't be routed), graph write, then the eligibility chain; returns explainable matches, a plan, routes and trace spans.";
sem IntakeWalker.conversation is "The user's latest message, in any language.";
sem IntakeWalker.user_id is "Stable per-visitor id; finds or creates the PersonNode.";
sem IntakeWalker.prior is "Profile returned on the previous turn, merged so follow-up answers refine the same case.";
