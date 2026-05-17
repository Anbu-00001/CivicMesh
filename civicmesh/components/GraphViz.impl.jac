"""Replay step logic for GraphViz."""

impl GraphViz.nodeColor(node_type: str) -> str {
    colors = {
        "Root": "#FFE500",
        "PersonNode": "#FFE500",
        "NeedNode": "#4488FF",
        "ResourceNode": "#00FF88",
        "EligibilityRuleNode": "#FFB344",
        "FormNode": "#FF88AA",
        "ApplicationNode": "#AA88FF"
    };
    return colors.get(node_type, "#444444");
}

impl GraphViz.renderEdge(e: list) -> JsxElement {
    e0 = str(e[0]);
    e1 = str(e[1]);
    src_list = [n for n in graph_nodes if str(n["id"]) == e0];
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if (not src_list) or (not tgt_list) {
        return <line/>;
    }
    src = src_list[0];
    tgt = tgt_list[0];
    is_active = (e0 in visited) and (e1 in visited);
    return
        <line
            key={e0 + "-" + e1}
            x1={str(src["x"])}
            y1={str(src["y"])}
            x2={str(tgt["x"])}
            y2={str(tgt["y"])}
            stroke={("rgba(255,229,0,0.35)" if is_active else "rgba(255,255,255,0.05)")}
            strokeWidth={("1.5" if is_active else "0.5")}
            style={{"transition": "all 0.4s ease"}}
        />;
}

impl GraphViz.renderNode(n: dict) -> JsxElement {
    is_visited = str(n["id"]) in visited;
    is_current = str(n["id"]) == current;
    color = nodeColor(str(n["type"]));
    return
        <g key={n["id"]} transform={"translate(" + str(n["x"]) + "," + str(n["y"]) + ")"}>
            {is_current and <circle
                r="22"
                fill="none"
                stroke={color}
                strokeWidth="1.5"
                opacity="0.35"
            />}
            <circle
                r="13"
                fill={(color if is_visited else "rgba(255,255,255,0.04)")}
                stroke={color}
                strokeWidth={("2" if is_current else "0.8")}
                opacity={("1" if is_visited else "0.35")}
                style={{"transition": "all 0.4s ease"}}
            />
            <text
                y="26"
                textAnchor="middle"
                fill={(color if is_visited else "rgba(255,255,255,0.25)")}
                fontSize="9"
                fontWeight={("600" if is_current else "400")}
                style={{"transition": "all 0.4s ease"}}
            >
                {n["label"]}
            </text>
        </g>;
}

impl GraphViz.renderLastEvent -> JsxElement {
    # Guarded inside the call site by `len(walker_events) > 0`, but we still
    # defensively check the entry. Critically we do NOT cast with `dict(...)`
    # because Jac compiles that to `Object.fromEntries(obj)`, which throws
    # on plain JS objects — the entry comes back from React state already as
    # an object, not as a list of [key, value] tuples.
    n = len(walker_events);
    if n == 0 {
        return <span/>;
    }
    last: Any = walker_events[n - 1];
    if not last {
        return <span/>;
    }
    w_raw = last["walker"];
    nd_raw = last["node"];
    st_raw = last["status"];
    w = str(w_raw) if w_raw else "";
    nd = str(nd_raw) if nd_raw else "";
    st = str(st_raw) if st_raw else "";
    return
        <div
            style={{
                "padding": "8px 18px",
                "borderTop": "0.5px solid rgba(255,255,255,0.05)",
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.35)",
                "display": "flex",
                "alignItems": "center",
                "gap": "6px"
            }}
        >
            <span style={{"color": "#FFE500"}}>{w}</span>
            <span>→</span>
            <span>{nd}</span>
            <span style={{"color": "#00FF88", "marginLeft": "4px"}}>{st}</span>
        </div>;
}

impl GraphViz.startReplay -> None {
    # Build the real traversal path from walker_events if we have any —
    # otherwise fall back to the demo path so first-time viewers still see
    # the graph come alive.
    is_playing = True;
    visited = [];
    current = "";
    replay_idx = 0;

    real_path: list = [];
    if walker_events and len(walker_events) > 0 {
        fired: list = [];
        ev_count = len(walker_events);
        i = 0;
        while i < ev_count {
            ev: Any = walker_events[i];
            w_raw = ev["walker"] if ev else "";
            w = str(w_raw) if w_raw else "";
            if w and (w not in fired) {
                fired = fired + [w];
            }
            i = i + 1;
        }
        for w in fired {
            node_list = walker_to_nodes[w] if w in walker_to_nodes else [];
            if node_list {
                for n in node_list {
                    if n not in real_path {
                        real_path = real_path + [n];
                    }
                }
            }
        }
    }

    # active_path is what stepReplay walks through — real when we have
    # session activity, demo path otherwise.
    active_path: list = real_path if len(real_path) > 0 else list(walk_path);
    stepReplay(0, active_path);
}

impl GraphViz.stepReplay(idx: int, path: list) -> None {
    # idx + path are passed as parameters (not read from React state) so
    # each setTimeout-scheduled recursive call advances correctly even when
    # the function closure was captured from an older render.
    n = len(path);
    if idx >= n {
        is_playing = False;
        current = "";
        return;
    }
    current = str(path[idx]);
    visited = list(path[:idx + 1]);
    replay_idx = idx + 1;
    if (idx + 1) < n {
        setTimeout(lambda { stepReplay(idx + 1, path); }, 500);
    } else {
        setTimeout(lambda { is_playing = False; current = ""; }, 500);
    }
}
