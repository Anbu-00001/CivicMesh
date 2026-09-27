"""Expected-cost multi-hop planning over `leads_to` edges.

When no program fits directly, the civic safety net is still a graph: shelter
intake files a re-housing referral, SNAP intake pre-qualifies WIC, and so on.
We search it with Yen's k-shortest loopless paths (Dijkstra inside), where an
edge's cost blends time, effort and the odds the next program says yes:

    cost(u→v) = days(u→v) + λ·difficulty(u→v) + μ·(−ln p_v)

p_v is v's eligibility × approval-posterior mean, so a fast hop into a program
that will probably reject you costs more than a slower, surer one. Costs stay
non-negative (−ln p ≥ 0), which keeps Dijkstra exact. A virtual super-source
fans out to every program the user can start today and a virtual super-sink
collects every worthwhile goal, so one Yen run returns the globally best k
routes. V≈40, E≈30: well under a millisecond.
"""

import heapq;
import math;

glob LAMBDA_DIFFICULTY: float = 10.0;
glob MU_RISK: float = 30.0;
glob DIFFICULTY_COST: dict = {"easy": 0.0, "moderate": 1.0, "hard": 3.0};
glob P_FLOOR: float = 0.05;
glob SRC: str = "__source__";
glob SNK: str = "__sink__";

"""Edge cost in day-equivalents."""
def edge_cost(days: float, difficulty: str, p_target: float) -> float {
    p = max(P_FLOOR, min(1.0, p_target));
    return float(days) + LAMBDA_DIFFICULTY * float(DIFFICULTY_COST.get(difficulty, 1.0)) + MU_RISK * (-math.log(p));
}

"""Dijkstra from src to dst. adj: {u: [(v, cost)]}. Returns (cost, path) or (inf, [])."""
def dijkstra(adj: dict, src: str, dst: str, banned_edges: set, banned_nodes: set) -> tuple {
    dist: dict = {src: 0.0};
    prev: dict = {};
    heap: list = [(0.0, src)];
    done: set = set();
    while heap {
        (d, u) = heapq.heappop(heap);
        if u in done { continue; }
        done.add(u);
        if u == dst { break; }
        for (v, c) in adj.get(u, []) {
            if v in banned_nodes or (u, v) in banned_edges { continue; }
            nd = d + float(c);
            if nd < dist.get(v, math.inf) {
                dist[v] = nd;
                prev[v] = u;
                heapq.heappush(heap, (nd, v));
            }
        }
    }
    if dst not in dist {
        return (math.inf, []);
    }
    path: list = [dst];
    while path[-1] != src {
        path.append(prev[path[-1]]);
    }
    path.reverse();
    return (dist[dst], path);
}

"""Total cost of a node path."""
def path_cost(adj: dict, path: list) -> float {
    total = 0.0;
    for i in range(len(path) - 1) {
        for (v, c) in adj.get(path[i], []) {
            if v == path[i + 1] {
                total += float(c);
                break;
            }
        }
    }
    return total;
}

"""Yen's algorithm: k loopless shortest paths from src to dst."""
def yen_k_shortest(adj: dict, src: str, dst: str, k: int) -> list {
    (c0, p0) = dijkstra(adj, src, dst, set(), set());
    if not p0 {
        return [];
    }
    A: list = [(c0, p0)];
    B: list = [];
    while len(A) < k {
        last = A[-1][1];
        for i in range(len(last) - 1) {
            spur = last[i];
            prefix = last[:i + 1];
            banned_edges: set = set();
            for (_c, p) in A {
                if len(p) > i and p[:i + 1] == prefix {
                    banned_edges.add((p[i], p[i + 1]));
                }
            }
            banned_nodes: set = set(prefix[:-1]);
            (sc, sp) = dijkstra(adj, spur, dst, banned_edges, banned_nodes);
            if sp {
                cand = prefix[:-1] + sp;
                cost = path_cost(adj, cand);
                if cand not in [p for (_c, p) in B] and cand not in [p for (_c, p) in A] {
                    B.append((cost, cand));
                }
            }
        }
        if not B {
            break;
        }
        B.sort(key=lambda t: tuple : t[0]);
        A.append(B.pop(0));
    }
    return A;
}

"""Best k escape routes from any start program to any goal program.

edges:   [{"from", "to", "days", "difficulty", "reason"}]
p_of:    {agency_name: success probability in (0, 1]}
sources: programs the user can act on now
goals:   programs worth reaching; goal_value in (0, 1] discounts the sink edge
"""
def plan_routes(edges: list, p_of: dict, sources: list, goals: dict, k: int = 3, min_hops: int = 1) -> list {
    adj: dict = {};
    meta: dict = {};
    for e in edges {
        u = str(e["from"]);
        v = str(e["to"]);
        c = edge_cost(float(e.get("days", 30)), str(e.get("difficulty", "moderate")), float(p_of.get(v, 0.3)));
        adj.setdefault(u, []).append((v, c));
        meta[(u, v)] = e;
    }
    for s in sources {
        adj.setdefault(SRC, []).append((str(s), 0.0));
    }
    for (g, value) in goals.items() {
        adj.setdefault(str(g), []).append((SNK, MU_RISK * (-math.log(max(P_FLOOR, min(1.0, float(value)))))));
    }
    routes: list = [];
    for (cost, path) in yen_k_shortest(adj, SRC, SNK, k * 3) {
        inner = [n for n in path if n != SRC and n != SNK];
        if len(inner) - 1 < min_hops {
            continue;
        }
        hops: list = [];
        total_days = 0;
        p_all = 1.0;
        for i in range(len(inner) - 1) {
            e = meta.get((inner[i], inner[i + 1]), {});
            d = int(e.get("days", 30));
            total_days += d;
            p_all = p_all * max(P_FLOOR, float(p_of.get(inner[i + 1], 0.3)));
            hops.append({
                "from": inner[i], "to": inner[i + 1], "days": d,
                "difficulty": str(e.get("difficulty", "moderate")),
                "reason": str(e.get("reason", ""))
            });
        }
        routes.append({
            "start": inner[0], "end": inner[-1], "hops": hops,
            "hop_count": len(hops), "total_days": total_days,
            "success_p": round(p_all, 3), "cost": round(cost, 1)
        });
        if len(routes) >= k {
            break;
        }
    }
    return routes;
}
