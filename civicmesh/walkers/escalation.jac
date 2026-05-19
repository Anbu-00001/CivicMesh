"""EscalationWalker — dead-end and all-denied handling over WebSocket.

Spawned on a PersonNode when EligibilityWalker has zero viable matches or
MemoryWalker observes every ApplicationNode has been denied. The walker is
exposed as a WebSocket endpoint so the client can receive streamed reasoning
steps (one `report` per ReAct iteration) instead of a single blocking reply.

Three tools are wired in for compose_escalation_message():
  - check_emergency_resources: pulls live ResourceNodes by category and capacity
  - find_appeal_orgs:           pulls legal advocacy options
  - assess_safety_risk:         flags situations needing crisis-line routing

The on_iteration callback caps the ReAct loop at `max_iterations` so a model
that keeps requesting tools cannot run forever — it returns ABORT_WITH_SUMMARY
so the user still gets a useful payload.
"""

import from graph.nodes { PersonNode, ResourceNode }
import from llm.stubs { EscalationContext, EscalationMessage, compose_escalation_message }
import from jaclang.runtimelib.builtin { restspec, APIProtocol }
import from byllm.lib { IterationAction, IterationContext }

@restspec(protocol=APIProtocol.WEBSOCKET)
walker EscalationWalker {
    has context: EscalationContext;
    has person_node: PersonNode;
    has iteration_count: int = 0;
    has max_iterations: int = 8;
    # Mirror of the final report so the spawning walker can read it after
    # spawn — `report` payloads flow only into the outermost walker's stream.
    has summary: dict = {};

    can escalate with PersonNode entry {
        # ReAct loop guard. Streams progress to the WebSocket client and
        # forces termination once max_iterations is reached so a misbehaving
        # model cannot loop forever.
        def iteration_guard(ctx: IterationContext) -> IterationAction {
            self.iteration_count += 1;
            report {
                "type": "escalation_step",
                "step": int(ctx.iteration),
                "message": "Scanning escalation path " + str(ctx.iteration) + "..."
            };
            if self.iteration_count >= self.max_iterations {
                return IterationAction.ABORT_WITH_SUMMARY;
            }
            return IterationAction.CONTINUE;
        }

        # Pull emergency and crisis resources for the user's need category and
        # location, with 211 prepended as a universal fallback. Capped at five
        # entries so the LLM prompt stays bounded.
        def check_emergency_resources(category: str, location_zip: str) -> list[str] {
            # Capture the local parameter under a distinct name so the edge-filter
            # predicate below doesn't compare the node's `category` attribute
            # against itself (which would always be True and pull every resource).
            target_category = category;
            emergency: list[str] = [];
            for r in [root --> [?:ResourceNode, category == target_category]] {
                if str(r.capacity) == "closed" {
                    continue;
                }
                desc = str(r.description);
                if len(desc) > 120 {
                    desc = desc[:120];
                }
                emergency.append(str(r.agency_name) + ": " + str(r.contact_phone) + " — " + desc);
            }
            has_211 = False;
            for line in emergency {
                if "211" in line {
                    has_211 = True;
                    break;
                }
            }
            if not has_211 {
                emergency = ["211 — Call or text 211: local resource referrals, 24/7, free, confidential"] + emergency;
            }
            return emergency[:5];
        }

        # Identify legal aid and advocacy organizations relevant to a denied
        # resource. The LLM uses this to surface appeal paths without us having
        # to enumerate them ourselves.
        def find_appeal_orgs(resource_name: str, denial_reason: str) -> list[str] {
            legal_orgs: list[str] = [];
            for r in [root --> [?:ResourceNode, category == "legal"]] {
                if str(r.capacity) == "closed" {
                    continue;
                }
                legal_orgs.append(str(r.agency_name) + ": " + str(r.contact_phone));
            }
            return legal_orgs[:3];
        }

        # Decide whether the user's situation should route to a crisis line.
        # Anchored on a short keyword set; the LLM uses the result to set
        # EscalationMessage.is_emergency.
        def assess_safety_risk(trigger_reason: str, urgency: str, denial_reasons: list[str]) -> bool {
            high_risk = ["homeless", "eviction", "domestic", "violence", "unsafe", "immediate", "shelter"];
            combined = (" ".join(denial_reasons) + " " + urgency).lower();
            for k in high_risk {
                if k in combined {
                    return True;
                }
            }
            return False;
        }

        # The user's language flows through context.profile.language. The
        # compose_escalation_message stub's docstring + the sem string on
        # NeedProfile.language together tell the model to write
        # personalized_message + appeal_options directly in that language,
        # eliminating the lossy post-translation hop.
        target_lang = "en";
        try {
            if self.context.profile.language {
                target_lang = str(self.context.profile.language);
            }
        } except Exception as _ex {}
        if not target_lang {
            target_lang = str(here.language) if here.language else "en";
        }

        escalation_msg: EscalationMessage = compose_escalation_message(
            context=self.context,
            tools=[check_emergency_resources, find_appeal_orgs, assess_safety_risk],
            on_iteration=iteration_guard
        );

        # Deterministic lead-line construction. The LLM was producing
        # category cross-talk (food prompts getting 988, housing prompts
        # getting food-bank leads, etc.) so we build the lead in walker
        # code based on context.profile.category plus simple keyword
        # checks for self-harm and domestic violence. The LLM only
        # contributes the empathetic tail in `personalized_message`.
        cat_raw = "";
        details_raw = "";
        try { cat_raw = str(self.context.profile.category).lower(); } except Exception as _ex {}
        try { details_raw = str(self.context.profile.details).lower(); } except Exception as _ex {}
        denial_blob = "";
        try {
            if self.context.denial_reasons {
                denial_blob = " ".join([str(x) for x in self.context.denial_reasons]).lower();
            }
        } except Exception as _ex {}
        scan_text = details_raw + " " + denial_blob;

        dv_kw = ["domestic violence", "domestic-violence", "safe house", "safe-house",
                 "safehouse", "abuse", "abused", "abusive", "battered", "stalker", "stalking"];
        selfharm_kw = ["suicide", "suicidal", "kill myself", "end my life",
                       "self harm", "self-harm", "want to die", "hurt myself"];

        is_dv = False;
        for k in dv_kw {
            if k in scan_text { is_dv = True; break; }
        }
        is_sh = False;
        for k in selfharm_kw {
            if k in scan_text { is_sh = True; break; }
        }

        lead_line = "";
        if is_sh {
            lead_line = "Call 988 Suicide and Crisis Lifeline: 988 — free, 24/7, confidential crisis counseling.";
        } elif is_dv {
            lead_line = "Call the National Domestic Violence Hotline: 1-800-799-7233 — 24/7 safe-house placement, free and confidential.";
        } elif cat_raw == "food" {
            lead_line = "Call 2-1-1: dial 2-1-1 — free 24/7 referral to your nearest food bank, SNAP office, and emergency food pantry.";
        } elif cat_raw == "housing" {
            lead_line = "Call 2-1-1: dial 2-1-1 — same-night emergency shelter placement and rapid re-housing referrals.";
        } elif cat_raw == "healthcare" {
            lead_line = "Call 2-1-1: dial 2-1-1 — sliding-scale clinic and Medicaid enrollment referrals in your area.";
        } elif cat_raw == "legal" {
            lead_line = "Call Legal Services Corporation: 1-800-815-9614 — free civil legal aid for eviction, immigration, and benefits appeals.";
        } else {
            lead_line = "Call 2-1-1: dial 2-1-1 — free 24/7 referral line for any social-services need.";
        }

        # Strip any phone-number / "Call X:" intro the LLM produced anyway,
        # then prepend our deterministic lead line. We split on blank lines
        # and drop leading paragraphs that look like a phone-number lead so
        # the LLM's "Call 988: 988 ..." attempt doesn't show up before our
        # category-correct lead.
        llm_tail = str(escalation_msg.personalized_message);
        # Normalize literal "\n" sequences the LLM sometimes emits as text
        try { llm_tail = llm_tail.replace("\\n\\n", "\n\n").replace("\\n", "\n"); } except Exception as _ex {}
        paragraphs: list = llm_tail.split("\n\n");
        cleaned: list = [];
        for p in paragraphs {
            ps = str(p).strip();
            if not ps { continue; }
            ps_lower = ps.lower();
            # Drop paragraphs that start with a "Call ..." or "Llama ..."
            # phone-number lead — those are the LLM's failed lead attempt.
            looks_like_lead = (ps_lower.startswith("call ")
                               or ps_lower.startswith("llama ")
                               or ps_lower.startswith("dial ")
                               or ps_lower.startswith("2-1-1")
                               or ps_lower.startswith("211")
                               or ps_lower.startswith("988")
                               or ps_lower.startswith("1-800"));
            if looks_like_lead and len(cleaned) == 0 {
                continue;
            }
            cleaned.append(ps);
        }
        tail_clean = "\n\n".join(cleaned);
        composed_message = lead_line;
        if tail_clean {
            composed_message = lead_line + "\n\n" + tail_clean;
        }

        payload = {
            "type": "escalation_complete",
            "trigger": str(self.context.trigger_reason),
            "is_emergency": bool(escalation_msg.is_emergency),
            "crisis_resources": list(escalation_msg.crisis_resources),
            "appeal_options": list(escalation_msg.appeal_options),
            "personalized_message": composed_message,
            "language": target_lang,
            "iterations_used": int(self.iteration_count)
        };
        self.summary = payload;
        report payload;
    }
}

sem EscalationWalker is "Crisis-routing walker. Spawned on a PersonNode when no resources match the user's NeedProfile or every ApplicationNode is denied. Composes a personalized escalation message via a byllm ReAct loop with three civic-resource tools, streamed over a WebSocket so the client gets each reasoning step as it happens.";
sem EscalationWalker.context is "Snapshot of the triggering scenario — NeedProfile + denial reasons + urgency. Fed to compose_escalation_message() as a single typed object so the LLM reasons over one structured input.";
sem EscalationWalker.person_node is "The PersonNode this escalation is for. The walker reads here.language and here.location_zip to localize the crisis reply.";
sem EscalationWalker.iteration_count is "ReAct loop counter incremented inside iteration_guard. Triggers ABORT_WITH_SUMMARY once max_iterations is exceeded.";
sem EscalationWalker.max_iterations is "Hard ceiling on ReAct iterations. Prevents a misbehaving model from looping indefinitely. Eight covers crisis composition with three tools.";
sem EscalationWalker.summary is "Mirror of the final report payload. Sibling walkers spawning this one read it via .summary because `report` only bubbles to the outermost walker's stream.";
