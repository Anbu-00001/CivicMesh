"""IntakeWalker — entry point for the CivicMesh pipeline.

Spawns at root, detects the user's language, finds or creates the PersonNode,
extracts a NeedProfile from the conversation, attaches a NeedNode via the
typed has_need edge, and then spawns EligibilityWalker against the NeedNode.

All cross-walker state flows through walker `has` fields; the graph itself
remains the single source of truth for persisted user state.
"""

import datetime;
import from graph.nodes { PersonNode, NeedNode, SessionInsight }
import from graph.edges { has_need, reflected_on }
import from llm.stubs {
    NeedProfile,
    LanguageProfile,
    extract_need_profile,
    detect_language_and_extract
}
import from walkers.eligibility { EligibilityWalker }
import from walkers.critique { CritiqueWalker }

walker IntakeWalker {
    has conversation: str;
    has user_id: str;
    # Walker chain event accumulator. Populated by the chain itself as
    # children fire (they `append` here through the spawning walker's
    # report payload), then handed to CritiqueWalker at the end so the
    # post-turn self-reflection has the same picture the client sees.
    has chain_events: list = [];

    can intake with `Root entry {
        ts = datetime.datetime.utcnow().isoformat();

        # Step 0 — Reflexion read-back. Before any LLM call, walk to the
        # existing PersonNode (if any) and pull the last 2 SessionInsight
        # headlines off the reflected_on edges. Prepended as a one-line
        # context prefix to the LLM input. Zero extra LLM cost; the
        # agent literally reads its own past performance as memory.
        reflection_prefix = "";
        prior_match = [root --> [?:PersonNode, user_id == self.user_id]];
        if prior_match {
            prior_person: Any = prior_match[0];
            past_insights = [prior_person ->:reflected_on:-> [?:SessionInsight]];
            if past_insights {
                # Sort by ISO timestamp descending — newest first.
                sorted_insights: list = list(past_insights);
                try {
                    sorted_insights.sort(key=lambda x : str(x.ts), reverse=True);
                } except Exception as _ex {}
                # Take last 2, build a one-line context prefix the LLM
                # treats as session history. Keeps token cost negligible.
                ctx_lines: list[str] = [];
                ci = 0;
                while ci < len(sorted_insights) and ci < 2 {
                    try {
                        ctx_lines = ctx_lines + [str(sorted_insights[ci].headline)];
                    } except Exception as _ex {}
                    ci = ci + 1;
                }
                if ctx_lines {
                    reflection_prefix = "[Context from agent self-reflection: " + " ".join(ctx_lines) + "] ";
                }
            }
        }
        # Reflexion headlines stay OUT of LLM inputs — they kept poisoning
        # category extraction (a prior housing turn would make food prompts
        # come back as "housing") and language detection (prior Spanish
        # text would make English prompts come back as "es"). The Reflexion
        # WRITE-back to SessionInsight is still useful for the telemetry
        # chart, but we no longer READ it into prompts for the live turn.
        # reflection_prefix remains computed above purely so the report
        # payload still surfaces whether prior insights existed.

        # Step 1a — heuristic language lock. If the prompt is overwhelmingly
        # ASCII with multiple English stopwords, force "en". Llama-3.1-8b
        # on NIM intermittently returns "es" for short, unambiguous English
        # questions (e.g. "Who do I call for a domestic-violence safe
        # house?") which then makes downstream LLMs reply in Spanish. The
        # heuristic eliminates that failure mode for English. Non-English
        # prompts fall through to the LLM detector unchanged.
        heuristic_lang = "";
        raw = str(self.conversation);
        if raw {
            # Pad with spaces so token-boundary substring checks like " i "
            # also catch words at the very start and end of the prompt.
            lowered = " " + raw.lower() + " ";
            ascii_count = 0;
            total_count = 0;
            for c in raw {
                total_count = total_count + 1;
                if ord(c) < 128 { ascii_count = ascii_count + 1; }
            }
            ascii_ratio = 0.0;
            if total_count > 0 {
                ascii_ratio = float(ascii_count) / float(total_count);
            }
            # English-distinctive markers — surrounded by spaces / punctuation
            # so we don't false-match inside Spanish or French words. These
            # spellings are essentially non-existent in major non-English
            # target languages (es / fr / de / pt / it / vi / hi-romanized).
            # Substring matching is bulletproof — no tokenize/strip step
            # that could break under jac's str semantics.
            en_markers = [
                " i ", " i'm ", " i've ", " i'll ", " i'd ", "i'm ", "i've ",
                " the ", " a ", " an ", " is ", " are ", " was ", " were ",
                " my ", " your ", " our ", " their ", " his ", " her ",
                " you ", " we ", " they ", " he ", " she ",
                " and ", " or ", " but ", " not ", " no ",
                " for ", " to ", " of ", " in ", " on ", " at ", " with ",
                " from ", " by ", " about ", " into ",
                " do ", " does ", " did ", " have ", " has ", " had ",
                " can ", " could ", " would ", " should ", " will ", " might ",
                " need ", " needed ", " want ", " wants ", " wanted ",
                " what ", " where ", " when ", " who ", " how ", " why ",
                " right ", " now ", " tonight ", " today ", " yesterday ",
                " help ", " call ", " find ", " lost ", " job ", " jobless ",
                " food ", " rent ", " house ", " home ", " shelter ",
                " family ", " kids ", " children ", " son ", " daughter ",
                " doctor ", " medicine ", " legal ", " lawyer ", " court ",
                " eviction ", " evicted ", " evict ",
                " domestic ", " violence ", " safe ", " emergency ",
                "?", " avoid "
            ];
            hit_count = 0;
            for m in en_markers {
                if m in lowered { hit_count = hit_count + 1; }
            }
            # Two independent signals must agree: prompt is overwhelmingly
            # ASCII AND contains multiple English-distinctive markers.
            if ascii_ratio >= 0.92 and hit_count >= 2 {
                heuristic_lang = "en";
            }
        }

        # Step 1b — LLM detection (only consulted when the heuristic is
        # not confident it's English).
        detected_lang_str: str = "";
        lang_profile: LanguageProfile;
        if heuristic_lang {
            detected_lang_str = heuristic_lang;
            lang_profile = LanguageProfile(detected_language=heuristic_lang, confidence=1.0, translated_intent=raw);
        } else {
            lang_profile = detect_language_and_extract(message=self.conversation);
            detected_lang_str = str(lang_profile.detected_language);
        }

        # Step 2: find existing PersonNode by user_id (idempotent across sessions)
        existing = [root --> [?:PersonNode, user_id == self.user_id]];
        person_node: PersonNode;
        if existing {
            person_node = existing[0];
        } else {
            created = root ++> PersonNode(
                user_id=self.user_id,
                language=detected_lang_str,
                location_zip="",
                income_bracket="",
                family_size=0,
                preferred_contact="online",
                created_at=ts
            );
            person_node = created[0];
        }
        # setattr is used in place of dotted assignment so the jaclang type
        # checker doesn't reject cross-file `has` writes — semantically the
        # same store, just opaque to the static analyzer.
        setattr(person_node, "language", detected_lang_str);

        # Step 3: extract structured NeedProfile from the RAW user prompt.
        # We deliberately do NOT prepend the Reflexion prefix here — see
        # the comment above. Past-session headlines were polluting category
        # extraction.
        profile = extract_need_profile(conversation=self.conversation);

        # Step 3b — keyword-based category override. The LLM's category
        # extraction is the single biggest failure mode in the chain: a
        # prompt like "I need food assistance for my family" sometimes
        # comes back classified as "housing" because the LLM latches onto
        # "family" and historical context. We deterministically override
        # whenever the raw prompt contains an unambiguous category keyword.
        # First match wins — checked in urgency order (food before housing
        # so "food shelter" stays food, etc).
        kw_lower = str(self.conversation).lower();
        kw_category = "";
        food_kw = ["food", "snap", "wic", "groceries", "grocery", "hungry", "hunger", "meal", "meals", "eat", "pantry", "feeding", "nutrition"];
        legal_kw = ["lawyer", "attorney", "legal", "court", "deport", "immigration", "asylum", "expunge", "appeal", "tenant rights"];
        healthcare_kw = ["doctor", "medicaid", "medicine", "prescription", "hospital", "dental", "therapy", "medical", "988", "mental health", "clinic", "checkup"];
        housing_kw = ["rent", "evict", "eviction", "shelter", "homeless", "housing", "section 8", "section8", "apartment", "landlord", "safe house", "safe-house", "safehouse", "domestic violence", "domestic-violence"];
        for k in food_kw {
            if k in kw_lower { kw_category = "food"; break; }
        }
        if not kw_category {
            for k in legal_kw {
                if k in kw_lower { kw_category = "legal"; break; }
            }
        }
        if not kw_category {
            for k in healthcare_kw {
                if k in kw_lower { kw_category = "healthcare"; break; }
            }
        }
        if not kw_category {
            for k in housing_kw {
                if k in kw_lower { kw_category = "housing"; break; }
            }
        }
        if kw_category {
            try { setattr(profile, "category", kw_category); } except Exception as _ex {}
        }

        # Lock NeedProfile.language to the heuristic-validated detection
        # result. Downstream byllm calls (compose_escalation_message,
        # generate_action_plan) read context.profile.language as the
        # target language directive.
        try {
            setattr(profile, "language", detected_lang_str);
        } except Exception as _ex {}

        # Step 4: attach the NeedNode via the typed has_need edge
        attached = person_node +>: has_need() :+> NeedNode(
            category=str(profile.category),
            urgency=str(profile.urgency),
            details=str(profile.details),
            created_at=ts
        );
        need_node: NeedNode = attached[0];

        # Step 5: backfill demographic fields the extractor surfaced
        if profile.income_bracket {
            setattr(person_node, "income_bracket", str(profile.income_bracket));
        }
        if int(profile.family_size) > 0 {
            setattr(person_node, "family_size", int(profile.family_size));
        }
        if profile.location_zip {
            setattr(person_node, "location_zip", str(profile.location_zip));
        }

        # Step 6: hand off to EligibilityWalker from the NeedNode. `report`
        # payloads only flow into the outermost walker's `.reports` list, so
        # child walkers mirror their final payload to `.summary` for us to
        # read after spawn.
        elig_walker = need_node spawn EligibilityWalker(
            profile=profile,
            person_node=person_node
        );
        elig_payload: dict = elig_walker.summary;

        # Step 7 — Reflexion write. CritiqueWalker reads the chain's
        # outcomes (eligible count, escalation/pathfinder/nav flags) and
        # writes a SessionInsight to the PersonNode. Zero LLM cost. Future
        # IntakeWalker turns read the most recent SessionInsight nodes
        # back as conversation prefix (see Step 0 above).
        eligible_count_out = 0;
        escalated_out = False;
        pathfinder_used_out = False;
        navigation_used_out = False;
        top_resource_out = "";
        try { eligible_count_out = int(elig_payload["eligible_count"]); } except Exception as _ex {}
        try { escalated_out = bool(elig_payload["escalated"]); } except Exception as _ex {}
        try { pathfinder_used_out = bool(elig_payload["pathfinder_used"]); } except Exception as _ex {}
        try {
            ap = elig_payload["action_plan"];
            if ap {
                navigation_used_out = True;
            }
        } except Exception as _ex {}
        # Pluck the highest-scored resource name so the SessionInsight
        # headline can name it. Anchors the reflection to a concrete
        # outcome, not just a count.
        try {
            top_matches_raw = elig_payload["top_matches"];
            if top_matches_raw and len(list(top_matches_raw)) > 0 {
                top_m: Any = list(top_matches_raw)[0];
                top_resource_out = str(top_m["resource"]);
            }
        } except Exception as _ex {}

        try {
            # Spawn from person_node (not root) so the walker enters
            # directly via PersonNode entry. Spawning from `root` ran into
            # a per-user-root scope issue where the freshly-created
            # PersonNode wasn't visible to a sibling walker's [root --> ...]
            # query.
            critique_walker = person_node spawn CritiqueWalker(
                user_id=self.user_id,
                walker_events=list(self.chain_events),
                user_prompt=str(self.conversation),
                eligible_count=eligible_count_out,
                escalated=escalated_out,
                pathfinder_used=pathfinder_used_out,
                navigation_used=navigation_used_out,
                need_category=str(profile.category) if profile.category else "",
                need_urgency=str(profile.urgency) if profile.urgency else "",
                top_resource=top_resource_out
            );
        } except Exception as _ex {
            # Critique failure is non-fatal — the user's reply still
            # goes through. We just lose this turn's self-reflection
            # record for the rolling Telemetry chart.
        }

        report {
            "language": detected_lang_str,
            "profile": {
                "category": str(profile.category),
                "urgency": str(profile.urgency),
                "details": str(profile.details)
            },
            "person_id": self.user_id,
            "eligibility_results": elig_payload,
            "reflection_prefix_used": bool(reflection_prefix)
        };
    }
}

sem IntakeWalker is "Entry-point walker for every chat turn. Detects language, finds-or-creates a PersonNode under root, lifts a NeedProfile from the transcript, attaches a NeedNode, then spawns EligibilityWalker against that NeedNode.";
sem IntakeWalker.conversation is "Full free-form chat transcript so far, in whatever language the user typed. Passed verbatim into detect_language_and_extract() and extract_need_profile().";
sem IntakeWalker.user_id is "Stable session identifier. Used to look up an existing PersonNode (returning user) or to seed PersonNode.user_id for a new one.";
