"""LiveTelemetryWalker — streams the user's graph topology over WebSocket.

The Graph tab in the client currently derives its node colors from the
local walker_events buffer, but the actual node existence list comes from
a hardcoded layout. LiveTelemetryWalker turns that into a real
subscription: a client opens `/ws/LiveTelemetryWalker`, the walker
traverses the per-user root, and emits one frame per node-class with the
current counts. The client can refresh on every chat turn to show the
graph actually growing as walkers run.

This walker is read-only (no graph mutation) and bounded by `max_frames`
so a misbehaving client cannot keep it streaming indefinitely.

Exposed as @restspec(protocol=APIProtocol.WEBSOCKET) so jac-scale
auto-registers `/ws/LiveTelemetryWalker` at server boot.
"""

import from graph.nodes {
    PersonNode,
    NeedNode,
    ResourceNode,
    EligibilityRuleNode,
    FormNode,
    ApplicationNode
}
import from jaclang.runtimelib.builtin { restspec, APIProtocol }


@restspec(protocol=APIProtocol.WEBSOCKET)
walker LiveTelemetryWalker {
    # Stream frame counter so the client can deduplicate / detect drops.
    has frame_count: int = 0;
    has max_frames: int = 1;
    # Final-frame mirror so sibling walkers can read it without subscribing
    # to the websocket themselves.
    has summary: dict = {};

    can stream with `Root entry {
        # Count nodes by class on the user's root. Each is one Jac edge-
        # filter expression — no Python loops, no SQL.
        person_count   = len([root --> [?:PersonNode]]);
        need_count     = len([root --> [?:NeedNode]]);
        resource_count = len([root --> [?:ResourceNode]]);
        rule_count     = len([root --> [?:EligibilityRuleNode]]);
        form_count     = len([root --> [?:FormNode]]);
        app_count      = len([root --> [?:ApplicationNode]]);

        # NeedNodes are reached via PersonNode → has_need → NeedNode, not
        # directly off root. We pick them up by scanning each PersonNode.
        person_nodes = [root --> [?:PersonNode]];
        person_need_count = 0;
        person_app_count = 0;
        for p in person_nodes {
            person_need_count += len([p ->:has_need:-> [?:NeedNode]]);
            person_app_count  += len([p ->:applied_to:-> [?:ApplicationNode]]);
        }

        self.frame_count += 1;
        frame = {
            "frame": self.frame_count,
            "PersonNode":          int(person_count),
            "NeedNode":             int(person_need_count),
            "ResourceNode":         int(resource_count),
            "EligibilityRuleNode":  int(rule_count),
            "FormNode":             int(form_count),
            "ApplicationNode":      int(person_app_count),
            "total_reachable":
                int(person_count) + int(person_need_count) + int(resource_count) +
                int(rule_count) + int(form_count) + int(person_app_count)
        };
        self.summary = frame;
        report frame;

        if self.frame_count >= self.max_frames {
            disengage;
        }
    }
}

import from graph.edges { has_need, applied_to }

sem LiveTelemetryWalker is "Streams a snapshot of the user's graph topology over WebSocket so the Graph tab can render real node counts per class. Read-only — no graph mutation. Bounded by max_frames to keep a misbehaving subscriber from holding the connection forever.";
sem LiveTelemetryWalker.frame_count is "Monotonic frame counter — clients use this to detect drops and dedupe.";
sem LiveTelemetryWalker.max_frames is "Hard cap on emitted frames. Default 1 produces a single snapshot; the client can re-spawn the walker for the next sample.";
sem LiveTelemetryWalker.summary is "Mirror of the final frame payload. Sibling walkers spawning this one read .summary because `report` only bubbles to the outermost walker stream.";
