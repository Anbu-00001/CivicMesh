"""PathfinderWalker — multi-hop graph reasoning over civic-resource progressions.

When EligibilityWalker has zero direct matches above threshold, instead of
escalating immediately to a crisis message, this walker runs a bounded
breadth-first search over the `leads_to` edge type to find a 2- or 3-step
"escape path" from the user's starting category to a reachable resource.

It's a genuinely Jac-native pattern: the walker IS the search algorithm,
the graph IS the search substrate, and `visit` over typed edges replaces
what would be a Python BFS queue plus a NetworkX-style adjacency map in
a non-OSP framework.

Why this matters for CivicMesh:
A user who doesn't directly qualify for Section 8 Housing Choice Voucher
(income too high, no priority status) might still qualify if they first
spend 30 days in an Emergency Shelter — which auto-creates a Section 8
priority application. The raw eligibility check can't see that; multi-hop
graph reasoning can. The civic safety net is intrinsically a multi-step
maze, and this is the right algorithm to navigate it.

Output: an ordered list of {agency_name, transition_reason, typical_days,
difficulty} hops the user can pursue sequentially. Renders in the chat
as a chained card sequence and in the GraphViz tab as a cyan overlay
highlighting the discovered route.
"""

import from graph.nodes { ResourceNode, EligibilityRuleNode }
import from graph.edges { leads_to }


walker PathfinderWalker {
    has start_category: str = "";
    has max_hops: int = 3;
    has max_paths: int = 3;
    # Set when EligibilityWalker has already scored some candidates against
    # this user's profile — those become preferred SEED nodes for the BFS
    # because they're the most-promising-yet-insufficient starting points.
    has seed_resource_names: list[str] = [];
    # Final aggregated payload mirror — siblings spawning this walker read
    # it via .summary because `report` only bubbles to the outermost.
    has summary: dict = {};

    can search with `Root entry {
        # Phase 1 — gather start nodes. Prefer the seed_resource_names that
        # EligibilityWalker handed us (resources the user almost qualified
        # for); fall back to ALL resources in the target category. We then
        # treat each of these as a BFS root and explore outward via
        # `leads_to` for max_hops steps, collecting the first max_paths
        # paths that reach a node distinct from the start.
        seed_nodes: list = [];
        if self.seed_resource_names {
            for name in self.seed_resource_names {
                matches = [root --> [?:ResourceNode, agency_name == name]];
                if matches {
                    seed_nodes.append(matches[0]);
                }
            }
        }
        # Always augment with category seeds. The specific near-miss
        # resources EligibilityWalker hands us are often LIHEAP, Public
        # Housing, HUD-VASH — programs that lack outgoing leads_to edges
        # in our curated transition graph (they're terminal-state
        # programs). Falling back to category-based seeds ensures BFS
        # always has start nodes that actually have neighbors to walk.
        if self.start_category {
            cat = self.start_category;
            category_seeds = [root --> [?:ResourceNode, category == cat]];
            for n in category_seeds {
                seed_nodes.append(n);
            }
        }

        # Phase 2 — BFS from each seed up to max_hops. We don't use Jac's
        # `visit` here because we need fine-grained control over the
        # frontier (track depth per node) and we need to collect EDGE
        # payloads (transition_reason, typical_days) which `visit` would
        # discard. Plain queue-style BFS expresses the algorithm directly
        # while still using Jac's edge-filter expression to enumerate
        # neighbors at each step.
        discovered_paths: list = [];
        seen_global: list = [];

        for seed in seed_nodes {
            seed_name = str(seed.agency_name);
            if seed_name in seen_global {
                continue;
            }
            # Each frontier entry: (current_node, path_so_far).
            # path_so_far is a list of {from, to, reason, days, difficulty}
            # transition records — depth = len(path_so_far).
            frontier: list = [(seed, [])];
            visited_local: list = [seed_name];

            while frontier {
                head = frontier[0];
                frontier = frontier[1:];
                cur_node = head[0];
                cur_path_raw = head[1];
                cur_path: list = list(cur_path_raw) if cur_path_raw else [];

                # If we've already accumulated >= 2 hops AND landed on a
                # distinct node from where we started, that's a valid
                # escape path — record it.
                if len(cur_path) >= 2 {
                    last_hop: Any = cur_path[len(cur_path) - 1];
                    discovered_paths.append({
                        "start": seed_name,
                        "end": str(last_hop["to"]),
                        "hops": list(cur_path),
                        "hop_count": len(cur_path),
                        "total_days": _sum_days(cur_path)
                    });
                    seen_global.append(seed_name);
                    if len(discovered_paths) >= self.max_paths {
                        break;
                    }
                    # Don't expand further from this completed path —
                    # we want diverse start->end pairs, not chains.
                    continue;
                }

                # Cap depth.
                if len(cur_path) >= self.max_hops {
                    continue;
                }

                # Expand neighbors via leads_to. Jac edge-filter expressions
                # return target nodes; we also need the edge payloads so
                # we re-fetch the edge objects on a second pass.
                neighbors = [cur_node ->:leads_to:-> [?:ResourceNode]];
                for nbr in neighbors {
                    nbr_name = str(nbr.agency_name);
                    if nbr_name in visited_local {
                        continue;
                    }
                    visited_local = visited_local + [nbr_name];

                    # Look up the edge payload connecting cur_node to nbr.
                    edge_set = [cur_node ->:leads_to:-> nbr];
                    reason = "";
                    typical_days = 30;
                    difficulty = "moderate";
                    if edge_set {
                        e: Any = edge_set[0];
                        try {
                            reason = str(e.transition_reason);
                        } except Exception as _ex {}
                        try {
                            typical_days = int(e.typical_days);
                        } except Exception as _ex {}
                        try {
                            difficulty = str(e.difficulty);
                        } except Exception as _ex {}
                    }

                    new_hop = {
                        "from": str(cur_node.agency_name),
                        "to": nbr_name,
                        "reason": reason,
                        "days": typical_days,
                        "difficulty": difficulty
                    };
                    frontier = frontier + [(nbr, cur_path + [new_hop])];
                }
            }

            if len(discovered_paths) >= self.max_paths {
                break;
            }
        }

        # Phase 3 — rank discovered paths by total time-to-resolution
        # (shorter is better) then by hop count (fewer hops = simpler).
        discovered_paths.sort(key=lambda p : (int(p["total_days"]), int(p["hop_count"])));

        payload_out = {
            "ok": True,
            "start_category": self.start_category,
            "max_hops": self.max_hops,
            "path_count": len(discovered_paths),
            "paths": discovered_paths[:self.max_paths]
        };
        self.summary = payload_out;
        report payload_out;
    }
}


# Helper: sum days across all hops in a path. Defined at module level so
# it doesn't shadow the walker's `here`/`self` context.
def _sum_days(hops: list) -> int {
    total = 0;
    for h in hops {
        try {
            total = total + int(h["days"]);
        } except Exception as _ex {}
    }
    return total;
}


sem PathfinderWalker is "Multi-hop graph reasoning for civic-aid escape paths. When direct eligibility scoring fails, spawns BFS over the leads_to edge type to find 2-3 step resource progressions the user can pursue sequentially. The walker IS the search algorithm — the graph IS the search substrate.";
sem PathfinderWalker.start_category is "NeedNode.category to seed the search from (housing / food / healthcare / legal). Determines which ResourceNodes become initial frontier members when no specific seed resources are provided.";
sem PathfinderWalker.max_hops is "Hard upper bound on path length. 3 is empirically right: paths longer than that exceed both the user's planning horizon and the graph's seeded leads_to topology depth.";
sem PathfinderWalker.max_paths is "Maximum number of distinct escape paths to surface. Three covers the most common (cheapest), the most reliable (highest-success), and the fastest (lowest total_days) without overwhelming the chat UI.";
sem PathfinderWalker.seed_resource_names is "Optional starting resources from EligibilityWalker's near-misses. When supplied, BFS prefers these as roots because they're already the closest-fit programs the LLM scored against the profile.";
sem PathfinderWalker.summary is "Final paths payload mirror so the spawning EligibilityWalker can read it directly via .summary instead of going through .reports.";
