"""NavigationWalker — turns ranked matches into an ordered, persisted plan.

Spawned on the PersonNode. engine/plan.jac orders steps with Smith's
weighted-shortest-processing-time rule (value ÷ effort, crisis lines pinned
first) and consolidates documents shared across steps. The plan is persisted
as one ApplicationNode per step on `applied_to`; untouched "pending" steps
from earlier turns are archived so the Action Plan tab shows the current case
rather than every past message. No LLM.
"""

import datetime;
import from graph.nodes { PersonNode, ApplicationNode }
import from graph.edges { applied_to }
import from engine.plan { build_plan }
import from engine.compose { span_begin, span_end }

walker NavigationWalker {
    has ranked: list = [];
    has urgency: str = "within_weeks";
    has language: str = "en";
    has trace: dict = {};
    has parent_span: str = "";
    has summary: dict = {};

    can plan with PersonNode entry {
        sp = span_begin(self.trace, "NavigationWalker plan", "INTERNAL", self.parent_span, {"gen_ai.agent.name": "NavigationWalker"});
        ts = datetime.datetime.utcnow().isoformat();
        plan = build_plan(list(self.ranked), self.urgency, self.language);

        archived = 0;
        for app in [here ->:applied_to:-> [?:ApplicationNode, status == "pending"]] {
            setattr(app, "status", "archived");
            setattr(app, "updated_at", ts);
            archived += 1;
        }
        for step in plan["steps"] {
            agency = str(step["agency_name"]);
            here +>: applied_to() :+> ApplicationNode(
                application_id=agency + "::" + ts,
                status="pending",
                resource_name=agency,
                updated_at=ts
            );
        }
        span_end(self.trace, sp, {"civicmesh.steps": len(plan["steps"]), "civicmesh.archived": archived});
        self.summary = plan;
    }
}

sem NavigationWalker is "Orders ranked matches into an action plan (Smith's rule), consolidates shared documents, and persists ApplicationNodes on applied_to edges.";
