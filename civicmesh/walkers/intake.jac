"""IntakeWalker — entry point and orchestrator for one chat turn.

Math-first pipeline, traced end to end:

  1. intake.parse     deterministic EN/ES parser (engine/parse.jac), < 1 ms,
                      merged with the profile carried from earlier turns
  2. gen_ai.chat      ONLY if the parser can't route the message: one typed
                      LLM call (understand_message), 6 s budget, then fall back
  3. graph.write      find-or-create PersonNode, attach NeedNode (has_need)
  4. EligibilityWalker → Navigation / Pathfinder / Escalation (all deterministic)
  5. CritiqueWalker   self-critique written back to the graph (SessionInsight on
                      reflected_on): quality score + the walkers and LLM calls
                      that actually ran, read off this turn's trace

The report carries the answer, the explainable match cards, the plan, the
escape routes, and an OpenTelemetry-shaped span list for the latency
waterfall. The client then calls NarrateWalker (the one LLM call) in the
background to localize and warm up the wording.
"""

import datetime;
import contextvars;
import concurrent.futures;
import from graph.nodes { PersonNode, NeedNode, ResourceNode }
import from walkers.seed { SeedWalker }
import from graph.edges { has_need }
import from llm.stubs { understand_message, pool_model_names }
import from engine.parse { parse_intake, clip_message }
import from engine.i18n { language_name, language_info, interpreter_card }
import from engine.stats { record_turn }
import from engine.privacy { redact, is_private_turn, need_summary, model_may_read_messages }
import from engine.compose { merge_profiles, new_trace, span_begin, span_end, export_spans }
import from walkers.eligibility { EligibilityWalker }
import from walkers.critique { CritiqueWalker }
import from walkers.narrate { sign_facts }

glob CATEGORIES: list = ["housing", "food", "healthcare", "legal"];
# The routing LLM call runs on a worker thread with a wall-clock deadline:
# litellm's own timeout is per HTTP read and the provider SDK can retry, so
# only a deadline the walker owns bounds what the user waits.
glob LLM_EXEC: Any = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="cm-llm");
glob SYNC_LLM_BUDGET_S: float = 3.5;

walker IntakeWalker {
    has conversation: str;
    has user_id: str;
    # Profile from the previous turn (client-held), so an answer to the
    # agent's follow-up question refines the same case.
    has prior: dict = {};
    # Key of the follow-up question this message answers (yes/no answers).
    has answering: str = "";
    # Language picked in the UI ("" / "auto" = detect). Wins over detection
    # for the reply language; routing still reads the message itself.
    has preferred_language: str = "";
    has chain_events: list = [];

    can intake with `Root entry {
        tr = new_trace();
        root_span = span_begin(tr, "invoke_agent CivicMesh", "SERVER", "", {"gen_ai.operation.name": "invoke_agent", "gen_ai.agent.name": "CivicMesh"});
        rid = root_span["span_id"];
        ts = datetime.datetime.utcnow().isoformat();
        # Bounded before anything reads or stores it (engine.parse.clip_message).
        text = clip_message(str(self.conversation));
        # A visitor whose SeedWalker call was lost (flaky proxy at sign-in) had
        # no programs, so every answer came back empty with no follow-up
        # question. Seeding is idempotent: do it here if the catalog is empty.
        if not [root --> [?:ResourceNode]] {
            root spawn SeedWalker(user_id=self.user_id);
        }

        sp = span_begin(tr, "intake.parse", "INTERNAL", rid);
        parsed = parse_intake(text);
        # A picked (or pinned-by-chip) language is the case language: an
        # English chip tapped in a Chinese conversation must not look like a
        # language switch and start a new case.
        pin = str(self.preferred_language or "").strip();
        if pin and pin != "auto" {
            parsed["language"] = pin;
            parsed["language_conf"] = 1.0;
        }
        profile = merge_profiles(dict(self.prior) if self.prior else {}, parsed, text, str(self.answering));
        span_end(tr, sp, {"civicmesh.category": profile["category"], "civicmesh.category_conf": profile["category_conf"], "civicmesh.language": profile["language"], "civicmesh.fields_known": profile["completeness"], "civicmesh.evidence_spans": len(parsed["evidence"])});

        llm_sync = False;
        llm_reason = str(profile.get("llm_reason", ""));
        llm_error = "";
        # Nothing to read (empty, emoji, a bare number): no LLM call — the
        # engine asks what the person needs instead.
        has_letters = len([c for c in text if c.isalpha()]) >= 2;
        if profile.get("needs_llm", False) and not has_letters {
            llm_reason = "no text to route";
        }
        # A crisis turn never leaves the server (engine/privacy.jac): the
        # fixed crisis routing answers it, no model sees the words.
        private_turn = is_private_turn(list(profile.get("flags", [])));
        if profile.get("needs_llm", False) and private_turn {
            llm_reason = "crisis turn — kept on the server, answered by fixed code";
        }
        # The user's words go to a hosted model only if the operator opts in
        # (CIVICMESH_MODEL_READS_MESSAGES=1, for a model under terms that allow
        # it). The NVIDIA trial API does not (§2.6(a), §4.3), so by default an
        # unroutable message gets the "what do you need?" question instead.
        if profile.get("needs_llm", False) and has_letters and not private_turn and not model_may_read_messages() {
            llm_reason = "not sent to any model (private by default) — asked what you need instead";
        }
        if profile.get("needs_llm", False) and has_letters and not private_turn and model_may_read_messages() {
            llm_sync = True;
            models = pool_model_names();
            sp = span_begin(tr, "chat understand_message", "CLIENT", rid, {"gen_ai.operation.name": "chat", "gen_ai.request.model": models[0] if models else "", "gen_ai.system": "litellm", "civicmesh.reason": llm_reason});
            try {
                fut = LLM_EXEC.submit(contextvars.copy_context().run, understand_message, redact(text));
                u = fut.result(timeout=SYNC_LLM_BUDGET_S);
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
                if not profile.get("citizenship") and str(u.citizenship) in ["citizen", "eligible_immigrant", "humanitarian", "non_citizen"] { profile["citizenship"] = str(u.citizenship); }
                if str(u.urgency) == "immediate" { profile["urgency"] = "immediate"; }
                profile["llm_summary"] = str(u.english_summary);
                span_end(tr, sp, {"civicmesh.category": profile["category"]});
            } except concurrent.futures.TimeoutError as _deadline {
                llm_error = "no answer within " + str(SYNC_LLM_BUDGET_S) + " s — the engine answered alone";
                span_end(tr, sp, {"error.type": "deadline_exceeded"}, "ERROR");
            } except Exception as ex {
                llm_error = str(ex)[:160];
                span_end(tr, sp, {"error.type": type(ex).__name__}, "ERROR");
            }
        }
        detected = str(profile.get("language", "") or "");
        chosen = str(self.preferred_language or "").strip();
        lang_code = chosen if (chosen and chosen != "auto") else detected;
        info = language_info(lang_code or "en");
        interpreter = str(info["tier"]) == "interpreter";
        # Mostly spoken languages (Mam, K'iche', Mixtec, …): answer in the
        # fallback language most speakers also use, plus an interpreter card.
        lang_out = (str(info["fallback"]) or "es") if interpreter else (lang_code or "en");
        narrate_lang = lang_out if interpreter else (lang_code or "auto");
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
            # The engine's reading, never the user's words: nothing typed is stored.
            details=need_summary(profile),
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
            # What actually ran this turn, read off the trace (not estimated).
            fired: list = ["IntakeWalker"];
            for x in tr["spans"] {
                nm = str(x["name"]).split(" ")[0];
                if nm.endswith("Walker") and nm not in fired { fired.append(nm); }
            }
            critique = person_node spawn CritiqueWalker(
                user_id=self.user_id,
                walker_events=[{"walker": w} for w in fired],
                llm_calls=(1 if llm_sync else 0) + 1,
                # The engine's reading, not the words: SessionInsight is stored.
                user_prompt=need_summary(profile),
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
        record_turn(self.user_id, lang_code or "?", str(profile["category"]), float(root_span.get("duration_ms", 0.0)), llm_sync, llm_error.startswith("no answer within"));
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
            # "auto": no language identified — the narrator mirrors the user's.
            "narrate_language": narrate_lang,
            "language_name": [str(info["name"]), str(info["endonym"])] if lang_code else language_name("en"),
            "language_info": info,
            "interpreter": interpreter_card(lang_code) if (lang_code and lang_code not in ["en", "es"]) else {},
            "profile": public_profile,
            "evidence": highlights,
            "category_scores": parsed["category_scores"],
            "reply": result.get("reply", ""),
            # The language `reply`, question, chips and plan text are in
            # (the user's when a message catalog covers it, else English).
            "reply_language": result.get("reply_language", "en"),
            "reply_en": result.get("reply_en", ""),
            "chip_labels": result.get("chip_labels", []),
            "ui": result.get("ui", {}),
            "question": result.get("question", {}),
            "matches": result.get("matches", []),
            "tiers": result.get("tiers", {}),
            "near_misses": result.get("near_misses", []),
            "plan": result.get("plan", {}),
            "routes": result.get("routes", []),
            "escalation": result.get("escalation", {}),
            "chips": result.get("chips", []),
            "facts": result.get("facts", ""),
            "facts_sig": sign_facts(str(result.get("facts", "")), [str(c) for c in list(result.get("chips", []))], str(narrate_lang)),
            "llm": {"sync_used": llm_sync, "reason": llm_reason, "error": llm_error, "models": pool_model_names(), "narrate": not private_turn, "budget_s": SYNC_LLM_BUDGET_S},
            # Privacy, as measured behavior: the words were neither stored nor
            # sent to a model (unless an operator opted in and the engine could
            # not route them); crisis turns are never sent.
            "privacy": {"private_turn": private_turn, "words_stored": False, "words_sent_to_model": llm_sync},
            "trace": {"trace_id": tr["trace_id"], "total_ms": root_span.get("duration_ms", 0.0), "spans": spans}
        };
    }
}

sem IntakeWalker is "Entry walker for every chat turn: deterministic parse (plus one LLM call only if the message can't be routed), graph write, then the eligibility chain; returns explainable matches, a plan, routes and trace spans.";
sem IntakeWalker.conversation is "The user's latest message, in any language.";
sem IntakeWalker.user_id is "Stable per-visitor id; finds or creates the PersonNode.";
sem IntakeWalker.prior is "Profile returned on the previous turn, merged so follow-up answers refine the same case.";
