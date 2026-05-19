"""MemoryWalker — read or update a returning user's session state.

Modes:
  "read_session"   — summarize the user's ApplicationNodes for the welcome screen
  "update_status"  — mark one ApplicationNode applied/denied/approved/withdrawn

When every ApplicationNode is denied after an update, the walker automatically
spawns EscalationWalker so the user is never left at a dead end.

Both modes share one `with PersonNode entry` handler that branches on
`self.mode`; declaring two separate `can` blocks with the same `with` clause
fires both on every visit, which we want to avoid. All graph mutations stay
inside the entry ability so `here` is typed as `PersonNode`.
"""

import datetime;
import from graph.nodes { PersonNode, ApplicationNode }
import from graph.edges { applied_to }
import from llm.stubs {
    NeedProfile,
    EscalationContext,
    summarize_session,
    generate_denial_next_step
}
import from walkers.escalation { EscalationWalker }

walker MemoryWalker {
    has user_id: str;
    has mode: str;
    has resource_name: str = "";
    has new_status: str = "";
    has denial_reason: str = "";

    can locate with `Root entry {
        matches = [root --> [?:PersonNode, user_id == self.user_id]];
        # Explicit length check; `not matches` is unreliable on JS empty
        # arrays (always truthy regardless of length).
        if len(matches) == 0 {
            report {"error": "No session found", "is_new_user": True};
            disengage;
        }
        visit matches;
    }

    can handle with PersonNode entry {
        # Snapshot the demographic fields once. They feed every stub call
        # below and we read them through `here`, which is correctly typed as
        # PersonNode only inside this entry ability.
        profile_stub = NeedProfile(
            category="",
            urgency="",
            details="",
            family_size=int(here.family_size),
            income_bracket=str(here.income_bracket),
            location_zip=str(here.location_zip),
            language=str(here.language)
        );

        if self.mode == "read_session" {
            apps = [here ->:applied_to:-> [?:ApplicationNode, status != "archived"]];

            approved: list = [];
            pending: list = [];
            denied: list = [];
            for app in apps {
                status = str(app.status);
                name = str(app.resource_name);
                if status == "approved" {
                    approved.append(name);
                } elif status == "denied" {
                    denied.append(name);
                } elif status == "pending" or status == "applied" {
                    pending.append(name);
                }
            }

            session_summary: any = None;
            if approved or pending or denied {
                session_summary = summarize_session(
                    approved=approved,
                    pending=pending,
                    denied=denied,
                    profile=profile_stub
                );
            }

            report {
                "has_history": bool(approved or pending or denied),
                "approved": approved,
                "pending": pending,
                "denied": denied,
                "language": str(here.language),
                "session_summary": session_summary,
                "application_count": len(apps)
            };
            return;
        }

        # mode == "update_status"
        ts = datetime.datetime.utcnow().isoformat();
        apps = [here ->:applied_to:-> [?:ApplicationNode, status != "archived"]];
        updated = False;

        for app in apps {
            if str(app.resource_name) != self.resource_name {
                continue;
            }
            setattr(app, "status", self.new_status);
            setattr(app, "updated_at", ts);
            if self.new_status == "denied" and self.denial_reason {
                setattr(app, "denial_reason", self.denial_reason);
                hint = generate_denial_next_step(
                    resource_name=self.resource_name,
                    denial_reason=self.denial_reason,
                    profile=profile_stub
                );
                setattr(app, "next_step_hint", str(hint));
            }
            if self.new_status == "applied" {
                setattr(app, "applied_at", ts);
            }

            # Outcome-learning: when an application reaches a terminal
            # decision (approved / denied), walk back to the
            # EligibilityRuleNode that gated the underlying ResourceNode
            # and update its Bayesian-style success prior. EligibilityWalker
            # weights LLM match_scores by this prior on subsequent turns,
            # so the graph genuinely learns from real outcomes. This is
            # the "graph that gets smarter every time someone uses it"
            # moment — pure Jac OSP, no external ML library.
            is_terminal = self.new_status == "approved" or self.new_status == "denied";
            if is_terminal {
                # Find the ResourceNode by name to walk to its rule.
                res_matches = [root --> [?:ResourceNode, agency_name == self.resource_name]];
                if res_matches {
                    rule_nodes = [res_matches[0] ->:governed_by:-> [?:EligibilityRuleNode]];
                    if rule_nodes {
                        rule_node: Any = rule_nodes[0];
                        # Increment attempts, conditionally increment approvals.
                        old_attempts = 0;
                        old_approvals = 0;
                        try { old_attempts = int(rule_node.prior_attempts); } except Exception as _ex {}
                        try { old_approvals = int(rule_node.prior_approvals); } except Exception as _ex {}
                        new_attempts = old_attempts + 1;
                        new_approvals = old_approvals;
                        if self.new_status == "approved" {
                            new_approvals = old_approvals + 1;
                        }
                        # Laplace-smoothed success rate to avoid 0/1 extremes
                        # on the first few datapoints — gives every rule a
                        # graceful warm-up before its prior moves significantly.
                        new_rate = (float(new_approvals) + 1.0) / (float(new_attempts) + 2.0);
                        setattr(rule_node, "prior_attempts", new_attempts);
                        setattr(rule_node, "prior_approvals", new_approvals);
                        setattr(rule_node, "prior_success_rate", new_rate);
                    }
                }
            }

            updated = True;
            break;
        }

        # If every application is now denied, escalate so the user never
        # ends up at a dead end with no further guidance.
        if updated and self.new_status == "denied" {
            refreshed = [here ->:applied_to:-> [?:ApplicationNode]];
            all_denied = len(refreshed) > 0 and all(str(a.status) == "denied" for a in refreshed);
            if all_denied {
                reasons: list = [];
                for a in refreshed {
                    reasons.append(str(a.denial_reason));
                }
                esc_context = EscalationContext(
                    trigger_reason="all_applications_denied",
                    profile=profile_stub,
                    denial_reasons=reasons,
                    urgency_level="immediate"
                );
                esc_walker = here spawn EscalationWalker(
                    context=esc_context,
                    person_node=here
                );
                esc_payload: dict = esc_walker.summary;
                report {
                    "updated": True,
                    "resource": self.resource_name,
                    "new_status": self.new_status,
                    "escalated": True,
                    "escalation": esc_payload
                };
                return;
            }
        }

        report {
            "updated": updated,
            "resource": self.resource_name,
            "new_status": self.new_status,
            "escalated": False
        };
    }
}

sem MemoryWalker is "Read or update a returning user's session state. In read_session mode summarizes ApplicationNodes for the welcome screen; in update_status mode mutates one ApplicationNode and auto-escalates when every application has been denied.";
sem MemoryWalker.user_id is "Stable identifier used to locate the existing PersonNode under root. The walker disengages with is_new_user=True if no match is found.";
sem MemoryWalker.mode is "Operating mode. One of: 'read_session' (return a SessionSummary), 'update_status' (mutate one ApplicationNode). Branched on inside the PersonNode entry ability.";
sem MemoryWalker.resource_name is "ApplicationNode.resource_name to mutate when mode='update_status'. Ignored in read_session mode.";
sem MemoryWalker.new_status is "Target ApplicationNode.status when mode='update_status'. One of: 'pending', 'applied', 'approved', 'denied', 'withdrawn'.";
sem MemoryWalker.denial_reason is "Free-form denial reason text. Populated only when new_status='denied'; drives generate_denial_next_step() to refresh next_step_hint.";
