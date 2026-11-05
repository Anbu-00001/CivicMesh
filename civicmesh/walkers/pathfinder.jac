"""PathfinderWalker — expected-cost escape routes over `leads_to` edges.

Real civic programs feed each other: shelter intake files a re-housing
referral, SNAP intake pre-qualifies WIC. The walker reads those typed edges
(transition_reason, typical_days, difficulty) straight off the graph and runs
Yen's k-shortest loopless paths (engine/paths.jac) from everything the user
can start today to every worthwhile goal, where an edge costs

    days + λ·difficulty + μ·(−ln P(next program says yes))

so routes are ranked by expected effort, not just hop count. No LLM.
"""

import from graph.nodes { ResourceNode }
import from graph.edges { leads_to }
import from engine.paths { plan_routes }
import from engine.compose { span_begin, span_end }
import from graph.catalog { shared_edges, shared_resources }

# leads_to edges are static after seeding: read them from the graph once per
# visitor per process.

walker PathfinderWalker {
    has start_category: str = "";
    has sources: list = [];
    has goals: dict = {};
    has p_of: dict = {};
    has max_paths: int = 3;
    has trace: dict = {};
    has parent_span: str = "";
    has summary: dict = {};

    can search with `Root entry {
        sp = span_begin(self.trace, "PathfinderWalker yen_k_shortest", "INTERNAL", self.parent_span, {"gen_ai.agent.name": "PathfinderWalker"});
        edges: list = shared_edges();
        sources = list(self.sources);
        goals = dict(self.goals);
        if not sources and self.start_category {
            cat = self.start_category;
            sources = [str(n.agency_name) for n in shared_resources() if str(n.category) == cat and str(n.capacity) == "open"];
        }
        routes: list = [];
        if sources and goals {
            routes = plan_routes(edges, dict(self.p_of), sources, goals, self.max_paths, 1);
        }
        span_end(self.trace, sp, {"civicmesh.edges": len(edges), "civicmesh.routes": len(routes)});
        self.summary = {"ok": True, "edge_count": len(edges), "path_count": len(routes), "paths": routes};
    }
}

sem PathfinderWalker is "Finds the k cheapest expected-cost multi-step routes through the leads_to program graph (Yen's algorithm over Dijkstra).";
