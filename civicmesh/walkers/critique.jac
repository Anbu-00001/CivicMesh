"""CritiqueWalker — Reflexion-style self-reflection for the agent chain.

Fires once at the end of every IntakeWalker chain. Reads the chain's
walker_events buffer (passed in from the caller), computes a session
quality score from heuristics on which walkers fired and what outcomes
they produced, then writes a SessionInsight node attached to the
PersonNode via the `reflected_on` edge.

The next IntakeWalker turn READS the last few SessionInsight nodes off
the same PersonNode and prepends a one-line summary to the conversation
the LLM sees — so the agent literally learns from its own past
performance via graph memory.

Zero LLM calls. Pure graph mutation. The substrate IS the memory.

This is Reflexion (Shinn et al, 2023) implemented as Jac walker code,
no external memory store, no PyTorch, no vector DB. The 2026 self-
improvement frontier in ~80 lines of OSP.
"""

import datetime;
import from graph.nodes { PersonNode, SessionInsight }
import from graph.edges { reflected_on }


walker CritiqueWalker {
    has user_id: str;
    has walker_events: list = [];
    has user_prompt: str = "";
    has eligible_count: int = 0;
    has escalated: bool = False;
    has pathfinder_used: bool = False;
    has navigation_used: bool = False;
    # Extra context for diverse headlines. Without these, every escalated
    # turn produced an identical "Prior turn escalated..." string,
    # rendering the rolling Telemetry timeline useless.
    has need_category: str = "";
    has need_urgency: str = "";
    has top_resource: str = "";
    has summary: dict = {};

    can reflect with PersonNode entry {
        # Distill walker_events into the set of distinct walkers that ran
        # this turn. The buffer can contain duplicates (running + complete
        # for the same walker); we dedupe by walker name.
        fired_names: list[str] = [];
        ev_count = len(self.walker_events);
        ei = 0;
        while ei < ev_count {
            try {
                ev: Any = self.walker_events[ei];
                w_raw = ev["walker"];
                w = str(w_raw) if w_raw else "";
                if w and (w not in fired_names) {
                    fired_names = fired_names + [w];
                }
            } except Exception as _ex {}
            ei = ei + 1;
        }

        # Cheap heuristic LLM-call estimator. Empirical breakdown:
        #   1 intake call + 1 language detect + up to 6 eligibility calls
        #   + 1 navigation (if used) OR 1+ escalation iterations
        #   + 1-2 translation calls
        # We don't try to be exact; this is for the rolling free-tier
        # budget chart in Telemetry, not for billing.
        llm_estimate = 2;
        if "EligibilityWalker" in fired_names {
            llm_estimate = llm_estimate + 6;
        }
        if self.navigation_used {
            llm_estimate = llm_estimate + 1;
        }
        if self.escalated {
            llm_estimate = llm_estimate + 2;
        }
        if "TranslateWalker" in fired_names {
            llm_estimate = llm_estimate + 1;
        }

        # Quality score formula. Baseline 50, lifted by successful
        # outcomes (navigation produced a plan, pathfinder found escape
        # paths) and dragged down by escalation (the agent had to bail
        # out to a crisis hotline). Capped to [0, 100].
        score = 50;
        if self.navigation_used { score = score + 30; }
        if self.pathfinder_used { score = score + 25; }
        if self.escalated { score = score - 15; }
        if self.eligible_count > 0 {
            bump = self.eligible_count * 5;
            if bump > 20 { bump = 20; }
            score = score + bump;
        }
        if score > 100 { score = 100; }
        if score < 0 { score = 0; }

        # Build a category-prefix string used in every headline so turns
        # on different domains/urgencies read distinctly even if all
        # three escalated. Example: "housing/immediate".
        cat_tag = "";
        if self.need_category {
            cat_tag = self.need_category;
        }
        if self.need_urgency {
            cat_tag = cat_tag + ("/" + self.need_urgency if cat_tag else self.need_urgency);
        }
        cat_prefix = ("[" + cat_tag + "] ") if cat_tag else "";

        # Prompt fingerprint: first 5 words, normalized. Anchors the
        # reflection back to what the user actually asked so timeline
        # rows don't all read the same.
        fp = "";
        try {
            parts = self.user_prompt.strip().split(" ");
            fp_parts = parts[:5];
            fp = " ".join(fp_parts);
            if len(fp) > 50 { fp = fp[:50] + "…"; }
        } except Exception as _ex {}

        # Headline a future IntakeWalker can prepend to its conversation
        # context. Diverse across (category, outcome, score, top resource)
        # so even consecutive escalations read as distinct memories.
        headline = "";
        if self.navigation_used and self.eligible_count > 0 {
            tail = "";
            if self.top_resource {
                tail = " · top match: " + self.top_resource;
            }
            headline = (cat_prefix + "Plan generated · "
                + str(self.eligible_count)
                + " resource" + ("s" if self.eligible_count != 1 else "")
                + " in tier · quality " + str(score)
                + tail);
        } elif self.pathfinder_used {
            headline = (cat_prefix
                + "Multi-hop pathfinder surfaced escape routes when direct eligibility failed (quality "
                + str(score) + ")");
        } elif self.escalated {
            headline = (cat_prefix
                + "Escalated · zero resources cleared the threshold for prompt: '" + fp + "' (quality "
                + str(score) + ")");
        } else {
            headline = (cat_prefix
                + "Intake completed without a strong outcome for prompt: '" + fp + "' (quality "
                + str(score) + ")");
        }

        prompt_snip = self.user_prompt;
        if len(prompt_snip) > 80 {
            prompt_snip = prompt_snip[:80];
        }

        ts = datetime.datetime.utcnow().isoformat();
        sid = "sess::" + ts;

        # Attach the SessionInsight to the PersonNode via reflected_on.
        # `here` is the PersonNode (PersonNode entry); the +>: edge :+>
        # syntax creates the edge and the target node in one shot.
        here +>: reflected_on() :+> SessionInsight(
            session_id=sid,
            ts=ts,
            walkers_fired=list(fired_names),
            llm_calls_est=int(llm_estimate),
            escalated=bool(self.escalated),
            pathfinder_used=bool(self.pathfinder_used),
            navigation_used=bool(self.navigation_used),
            eligible_count=int(self.eligible_count),
            quality_score=int(score),
            headline=str(headline),
            user_prompt_snippet=str(prompt_snip)
        );

        payload = {
            "ok": True,
            "session_id": sid,
            "quality_score": int(score),
            "headline": headline,
            "walkers_fired": list(fired_names),
            "llm_calls_est": int(llm_estimate)
        };
        self.summary = payload;
        report payload;
    }
}


# Companion read walker — exposes the recent SessionInsight nodes for
# this user to the Telemetry panel via a normal /walker/ REST call.
# Read-only, no graph mutation.
walker ReflectionReadWalker {
    has user_id: str;
    has max_insights: int = 8;
    has summary: dict = {};

    can locate with `Root entry {
        # Find this user's PersonNode under the authenticated root, then
        # visit it so the collect ability fires.
        matches = [root --> [?:PersonNode, user_id == self.user_id]];
        # Explicit length check — `not matches` would be `![]` which is
        # `false` in JS because arrays are always truthy.
        if len(matches) == 0 {
            # Cold-start: no PersonNode yet. Return an empty array rather
            # than failing — the Telemetry panel polls this on every chat
            # tab mount and an error would noise the dev console.
            payload = {"ok": True, "insights": [], "count": 0};
            self.summary = payload;
            report payload;
            disengage;
        }
        visit matches;
    }

    can collect with PersonNode entry {
        all_insights = [here ->:reflected_on:-> [?:SessionInsight]];
        rows: list = [];
        for ins in all_insights {
            try {
                rows.append({
                    "session_id": str(ins.session_id),
                    "ts": str(ins.ts),
                    "walkers_fired": list(ins.walkers_fired),
                    "llm_calls_est": int(ins.llm_calls_est),
                    "escalated": bool(ins.escalated),
                    "pathfinder_used": bool(ins.pathfinder_used),
                    "navigation_used": bool(ins.navigation_used),
                    "eligible_count": int(ins.eligible_count),
                    "quality_score": int(ins.quality_score),
                    "headline": str(ins.headline),
                    "user_prompt_snippet": str(ins.user_prompt_snippet)
                });
            } except Exception as _ex {}
        }
        # Newest first (string-sortable ISO timestamps descend lexically).
        rows.sort(key=lambda r : str(r["ts"]), reverse=True);
        rows = rows[:self.max_insights];

        payload = {"ok": True, "insights": rows, "count": len(rows)};
        self.summary = payload;
        report payload;
    }
}


sem CritiqueWalker is "Reflexion-style self-reflection. Runs once at the end of each chat turn, computes a session quality score from walker chain telemetry (zero LLM cost), and writes a SessionInsight node attached to the PersonNode. The agent's memory of its own past performance IS the graph.";
sem CritiqueWalker.user_id is "Stable session identifier used to find the PersonNode this critique attaches to.";
sem CritiqueWalker.walker_events is "Full walker_events buffer from the just-completed chain. Drives the distinct-walker-set computation and the LLM-call estimator.";
sem CritiqueWalker.user_prompt is "Original user prompt that triggered the turn. First 80 chars become the SessionInsight snippet for the Telemetry timeline.";
sem CritiqueWalker.eligible_count is "Count of eligible resources EligibilityWalker found this turn. Lifts the quality score.";
sem CritiqueWalker.escalated is "True when the chain routed to EscalationWalker. Drags the quality score down.";
sem CritiqueWalker.pathfinder_used is "True when PathfinderWalker found a multi-hop escape path. Counts as a positive outcome.";
sem CritiqueWalker.navigation_used is "True when NavigationWalker produced a non-empty ActionPlan. The cleanest positive signal.";
sem CritiqueWalker.summary is "Mirror of the final SessionInsight payload so the caller can read it after spawn without going through .reports.";

sem ReflectionReadWalker is "Read-only walker that returns the recent SessionInsight nodes for a user, newest first. The Telemetry panel polls this to render the rolling self-reflection chart.";
sem ReflectionReadWalker.user_id is "Session identifier of the PersonNode whose SessionInsights to fetch.";
sem ReflectionReadWalker.max_insights is "Hard cap on how many insights to return. Eight covers the Telemetry chart without making the payload heavy.";
sem ReflectionReadWalker.summary is "Mirror of the final insights payload.";
