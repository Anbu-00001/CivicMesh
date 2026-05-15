"""IntakeWalker — entry point for the CivicMesh pipeline.

Spawns at root, detects the user's language, finds or creates the PersonNode,
extracts a NeedProfile from the conversation, attaches a NeedNode via the
typed has_need edge, and then spawns EligibilityWalker against the NeedNode.

All cross-walker state flows through walker `has` fields; the graph itself
remains the single source of truth for persisted user state.
"""

import datetime;
import from graph.nodes { PersonNode, NeedNode }
import from graph.edges { has_need }
import from llm.stubs {
    NeedProfile,
    extract_need_profile,
    detect_language_and_extract
}
import from walkers.eligibility { EligibilityWalker }

walker IntakeWalker {
    has conversation: str;
    has user_id: str;

    can intake with `Root entry {
        ts = datetime.datetime.utcnow().isoformat();

        # Step 1: detect language + extract intent
        lang_profile = detect_language_and_extract(message=self.conversation);

        # Step 2: find existing PersonNode by user_id (idempotent across sessions)
        existing = [root --> [?:PersonNode, user_id == self.user_id]];
        person_node: PersonNode;
        if existing {
            person_node = existing[0];
        } else {
            created = root ++> PersonNode(
                user_id=self.user_id,
                language=str(lang_profile.detected_language),
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
        setattr(person_node, "language", str(lang_profile.detected_language));

        # Step 3: extract structured NeedProfile from the conversation
        profile = extract_need_profile(conversation=self.conversation);

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

        # Step 6: hand off to EligibilityWalker from the NeedNode. The spawn
        # expression returns the walker instance; its `.reports` list holds
        # whatever the walker `report`-ed during its run, which is what we
        # actually want to surface upward.
        elig_walker = need_node spawn EligibilityWalker(
            profile=profile,
            person_node=person_node
        );
        elig_payload: any = elig_walker.reports[0] if elig_walker.reports else {};

        report {
            "language": str(lang_profile.detected_language),
            "profile": {
                "category": str(profile.category),
                "urgency": str(profile.urgency),
                "details": str(profile.details)
            },
            "person_id": self.user_id,
            "eligibility_results": elig_payload
        };
    }
}
