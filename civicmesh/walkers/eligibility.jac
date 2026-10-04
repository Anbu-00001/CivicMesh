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
import from engine.compose { span_begin, span_end, compose_reply, reply_language }
import from engine.messages { msg, quick_options, ui_labels }
import from engine.plan { build_plan }
import from walkers.navigation { NavigationWalker }
import from walkers.pathfinder { PathfinderWalker }
import from walkers.escalation { EscalationWalker }

# Category defaults, as message keys (data/i18n): the English text is the
# payload the engine parses, the label is shown in the user's language.
glob CHIPS: dict = {
    "housing": ["chip.housing.0", "chip.housing.1", "chip.housing.2"],
    "food": ["chip.food.0", "chip.food.1", "chip.food.2"],
    "healthcare": ["chip.healthcare.0", "chip.healthcare.1", "chip.healthcare.2"],
    "legal": ["chip.legal.0", "chip.legal.1", "chip.legal.2"]
};

"""Short program name for chip text: the name before any parenthesis
("SNAP (Supplemental …)" → SNAP, "Public Housing (HUD)" → Public Housing —
the parenthesis holds an expansion or the agency, never the program)."""
def chip_name(name: str) -> str {
    n = str(name);
    if "(" in n and n.index("(") > 0 {
        return n[:n.index("(")].strip();
    }
    return n;
}

"""Follow-up suggestions that fit this case, not a fixed list per category.

"How do I apply for X?" for the best match; a situation chip only when a
program is waiting on exactly that fact (a child under 5 for WIC, children
for school meals); the category defaults fill the rest, minus any that
assume facts the person hasn't mentioned (kids, a tenancy). A chip the
person already sent (it's in the case text, as a tapped chip is sent as its
English text) is not offered again.
"""
def chips_for(ranked: list, profile: dict, lang: str = "en") -> list {
    flags = list(profile.get("flags", []));
    asked = str(profile.get("case_text", "")).lower();
    keyed: list = [];
    # "How do I apply for X?" only for programs with a real application
    # (a food bank or community fridge has nothing to apply for).
    likely = [s for s in ranked if s["tier"] in ["likely", "possible", "needs_info"] and not s.get("pinned", False)
              and int(dict(s.get("form", {}) or {}).get("estimated_minutes", 0) or 0) >= 20];
    if likely {
        keyed.append(["chip.apply", {"program": chip_name(likely[0]["resource_name"])}]);
    }
    asks: list = [];
    for s in ranked[:6] {
        for a in list(s.get("asks", [])) {
            if a not in asks { asks.append(a); }
        }
    }
    if "young_child" in asks and "children" not in flags { keyed.append(["chip.young_child", {}]); }
    elif "children" in asks and "children" not in flags { keyed.append(["chip.children", {}]); }
    if "homeless" in asks and "homeless" not in flags { keyed.append(["chip.homeless", {}]); }
    out: list = [[msg("en", k[0], k[1]), msg(lang, k[0], k[1])] for k in keyed];
    out = [o for o in out if o[0].lower() not in asked];
    for key in list(CHIPS.get(str(profile.get("category", "")), CHIPS["housing"])) {
        if len(out) >= 3 { break; }
        c = msg("en", key);
        if c.lower() in asked { continue; }
        if ("kids" in c or "children" in c) and "children" not in flags { continue; }
        if likely and chip_name(likely[0]["resource_name"]) in c { continue; }
        if c not in [o[0] for o in out] { out.append([c, msg(lang, key)]); }
    }
    # [English payload, label in the user's language]
    return out[:3];
}

"""The answer to a turn that asks for nothing (see IntakeWalker), in the shape
of EligibilityWalker's summary: a short reply and one question, nothing else.

Small talk in a case re-asks the question still open ("One question to
sharpen this: …"); otherwise it's "What do you need help with most right
now?", which a message the engine couldn't read prefaces with "I'm not sure
yet what kind of help you need".
"""
def quiet_summary(profile: dict, lang: str, pending: str) -> dict {
    ui_lang = reply_language(lang);
    small_talk = bool(profile.get("small_talk"));
    key = pending if (small_talk and profile.get("category") and pending and pending != "need") else "need";
    replies: dict = {};
    for l in ([ui_lang] if ui_lang == "en" else [ui_lang, "en"]) {
        q = question_for(key, l);
        replies[l] = msg(l, "r.question", {"question": q}) if key != "need" else (q if small_talk else msg(l, "r.unsure"));
    }
    return {
        "reply": replies[ui_lang], "reply_language": ui_lang, "reply_en": replies.get("en", "") if ui_lang != "en" else "",
        "question": {"key": key, "text": question_for(key, ui_lang), "affects": 0, "gain": 0.0, "affects_label": "", "options": quick_options(key, ui_lang)},
        "matches": [], "tiers": {"likely": 0, "possible": 0, "needs_info": 0, "unlikely": 0}, "near_misses": [],
        "plan": {"steps": []}, "routes": [], "escalation": {}, "chips": [], "chip_labels": [],
        "ui": ui_labels(ui_lang), "facts": ""
    };
}

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
    # What the hosted narration model may see: the kind of need and the
    # engine's answer. Not the person's words, income, household, age,
    # location or immigration status (the "met" criteria carry those).
    lines.append("need: " + str(profile.get("category", "")) + " (" + str(profile.get("urgency", "")) + ")");
    for s in list(ranking.get("ranked", []))[:4] {
        lines.append("- " + s["resource_name"] + " | " + s["tier"] + " | " + s["contact_phone"]);
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
        # Sentences shown to the user: their language when a message catalog
        # covers it (the scoring text underneath stays EN/ES).
        ui_lang = reply_language(self.language);

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
        question = question_for(str(ask["key"]), ui_lang) if ask["key"] else "";
        span_end(tr, sp, {"civicmesh.scored": ranking["all_count"], "civicmesh.likely": ranking["tiers"]["likely"], "civicmesh.ask": str(ask["key"])});

        ranked = list(ranking["ranked"]);
        # Nothing routed the message: say so and ask (compose: r.unsure), don't
        # present housing programs as if they'd been asked for, don't write
        # verdict edges for a guess, and don't archive an earlier plan. Only a
        # pinned crisis line survives.
        if self.profile.get("defaulted_category") {
            ranked = [s for s in ranked if s.get("pinned", False)];
        }

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

        plan: dict = {"steps": []};
        if ranked {
            nav = self.person_node spawn NavigationWalker(
                ranked=ranked, urgency=str(self.profile.get("urgency", "within_weeks")),
                language=ui_lang, trace=tr, parent_span=self.parent_span
            );
            plan = nav.summary;
        }

        p_of: dict = {};
        for s in ranked { p_of[s["resource_name"]] = float(s["p_eligible"]) * float(s["approval"]["mean"]); }
        sources = [s["resource_name"] for s in ranked if s["tier"] in ["likely", "possible"]];
        goals: dict = {};
        for s in ranked {
            if s["capacity"] == "waitlist" or s["tier"] in ["needs_info", "unlikely"] {
                goals[s["resource_name"]] = max(0.3, float(s["p_eligible"]));
            }
        }
        guessed = bool(self.profile.get("defaulted_category"));
        routes: list = [];
        if not guessed {
            pf = root spawn PathfinderWalker(
                start_category=str(self.profile.get("category", "")),
                sources=sources, goals=goals, p_of=p_of, trace=tr, parent_span=self.parent_span,
                cache_key=str(self.person_node.user_id)
            );
            routes = list(pf.summary.get("paths", []));
        }

        flags = list(self.profile.get("flags", []));
        escalation: dict = {};
        credible = ranking["tiers"]["likely"] + ranking["tiers"]["possible"];
        # "No credible match" means something when a need was named, not when
        # the engine guessed one: a guess gets no shelter-placement crisis box.
        if (credible == 0 and not guessed) or "self_harm" in flags or "dv" in flags {
            esc = self.person_node spawn EscalationWalker(
                category=str(self.profile.get("category", "")), flags=flags,
                language=ui_lang, ranked=ranked, trace=tr, parent_span=self.parent_span
            );
            escalation = esc.summary;
        }

        reply = compose_reply(ui_lang, self.profile, ranking, plan, routes, question);
        # The same answer in English, composed from the same numbers: shown on
        # request under a catalog translation so a bilingual helper can check it
        # (catalogs are machine-drafted until a native speaker reviews them).
        reply_en = "";
        if ui_lang != "en" {
            plan_en = build_plan(ranked, str(self.profile.get("urgency", "within_weeks")), "en");
            reply_en = compose_reply("en", self.profile, ranking, plan_en, routes, (question_for(str(ask["key"]), "en") if ask["key"] else ""));
        }
        chips = [] if guessed else chips_for(ranked, self.profile, ui_lang);
        qkey = str(ask["key"]);
        self.summary = {
            "reply": reply,
            "reply_language": ui_lang,
            "reply_en": reply_en,
            "question": {
                "key": qkey, "text": question, "affects": int(ask["affects"]), "gain": float(ask["gain"]),
                "affects_label": msg(ui_lang, "affects", {"n": int(ask["affects"])}) if int(ask["affects"]) > 0 else "",
                "options": quick_options(qkey, ui_lang) if qkey else []
            },
            "matches": ranked,
            "tiers": ranking["tiers"],
            "near_misses": ranking["near_misses"],
            "plan": plan,
            "routes": routes,
            "escalation": escalation,
            "chips": [c[0] for c in chips],
            "chip_labels": [c[1] for c in chips],
            "ui": ui_labels(ui_lang),
            # What the narrator may say: only what was understood. A guessed
            # need would come back as "it sounds like you need housing".
            "facts": "" if guessed else facts_for(ranking, plan, question, self.profile)
        };
    }
}

sem EligibilityWalker is "Scores every program in the graph against the profile with the deterministic engine, then spawns Navigation, Pathfinder and (if needed) Escalation.";
