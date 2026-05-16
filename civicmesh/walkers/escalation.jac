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
            emergency: list[str] = [];
            for r in [root --> [?:ResourceNode, category == category]] {
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

        escalation_msg: EscalationMessage = compose_escalation_message(
            context=self.context,
            tools=[check_emergency_resources, find_appeal_orgs, assess_safety_risk],
            on_iteration=iteration_guard
        );

        payload = {
            "type": "escalation_complete",
            "trigger": str(self.context.trigger_reason),
            "is_emergency": bool(escalation_msg.is_emergency),
            "crisis_resources": list(escalation_msg.crisis_resources),
            "appeal_options": list(escalation_msg.appeal_options),
            "personalized_message": str(escalation_msg.personalized_message),
            "iterations_used": int(self.iteration_count)
        };
        self.summary = payload;
        report payload;
    }
}
