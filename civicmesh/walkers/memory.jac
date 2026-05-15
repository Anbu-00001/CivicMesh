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
        if not matches {
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
            apps = [here ->:applied_to:-> [?:ApplicationNode]];

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
        apps = [here ->:applied_to:-> [?:ApplicationNode]];
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
                esc_payload: any = esc_walker.reports[-1] if esc_walker.reports else {};
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
