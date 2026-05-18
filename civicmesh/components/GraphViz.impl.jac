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

impl GraphViz.edgeWalkerColor(e0: str, e1: str) -> str {
    # Derive the beam color from whichever walker is responsible for the
    # target node — gives each beam a "house color" tied to its agent.
    walker_color_map = {
        "IntakeWalker":      "#FFE500",
        "EligibilityWalker": "#00FF88",
        "NavigationWalker":  "#FF88AA",
        "MemoryWalker":      "#AA88FF",
        "EscalationWalker":  "#FF4444"
    };
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if tgt_list {
        w_raw = tgt_list[0]["walker"];
        w = str(w_raw) if w_raw else "";
        if w in walker_color_map {
            return str(walker_color_map[w]);
        }
    }
    return "#FFE500";
}

impl GraphViz.renderEdge(e: dict) -> JsxElement {
    e0 = str(e["src"]);
    e1 = str(e["tgt"]);
    src_list = [n for n in graph_nodes if str(n["id"]) == e0];
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if (not src_list) or (not tgt_list) {
        return <line/>;
    }
    src = src_list[0];
    tgt = tgt_list[0];
    is_active = (e0 in visited) and (e1 in visited);

    # When "Why this path?" is on, dim non-visited edges further and brighten
    # visited ones in their type-relation color so the actual chosen route
    # reads as a thicker colored ribbon under the labels.
    stroke_color = "rgba(255,255,255,0.05)";
    stroke_width = "0.5";
    if is_active {
        if show_why_path {
            stroke_color = "rgba(68,136,255,0.55)";
            stroke_width = "2";
        } else {
            stroke_color = "rgba(255,229,0,0.35)";
            stroke_width = "1.5";
        }
    } elif show_why_path {
        stroke_color = "rgba(255,255,255,0.03)";
    }

    return
        <line
            key={e0 + "-" + e1}
            x1={str(src["x"])}
            y1={str(src["y"])}
            x2={str(tgt["x"])}
            y2={str(tgt["y"])}
            stroke={stroke_color}
            strokeWidth={stroke_width}
            style={{"transition": "all 0.4s ease"}}
        />;
}

impl GraphViz.renderEdgeLabel(e: dict) -> JsxElement {
    # Mid-edge pill rendering the schema-level relation type. Only fires when
    # show_why_path is True and the edge actually participated in the
    # walker's traversal — labelling every static edge would clutter the
    # canvas and obscure the actual chosen route.
    e0 = str(e["src"]);
    e1 = str(e["tgt"]);
    src_list = [n for n in graph_nodes if str(n["id"]) == e0];
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if (not src_list) or (not tgt_list) {
        return <g/>;
    }
    is_active = (e0 in visited) and (e1 in visited);
    if not is_active {
        return <g/>;
    }
    src = src_list[0];
    tgt = tgt_list[0];
    mx = (int(src["x"]) + int(tgt["x"])) // 2;
    my = (int(src["y"]) + int(tgt["y"])) // 2;
    label = str(e["label"]);
    # Width of the pill background scales with label length so single-word
    # labels don't get a giant trailing block.
    pill_w = 8 + (len(label) * 5);
    return
        <g key={"lbl-" + e0 + "-" + e1}>
            <rect
                x={str(mx - (pill_w // 2))}
                y={str(my - 7)}
                width={str(pill_w)}
                height="14"
                rx="7"
                fill="#0A0A0A"
                stroke="rgba(68,136,255,0.5)"
                strokeWidth="0.6"
            />
            <text
                x={str(mx)}
                y={str(my + 3)}
                textAnchor="middle"
                fill="#4488FF"
                fontSize="8.5"
                fontWeight="600"
                style={{"fontFamily": "ui-monospace, monospace", "letterSpacing": "0.02em"}}
            >
                {label}
            </text>
        </g>;
}

impl GraphViz.renderEdgeDot(e: dict) -> JsxElement {
    # Animated traveling dot along visited edges. Uses SMIL <animate> on
    # cx/cy attributes — broadly supported, no CSS keyframes needed, and the
    # dot resets cleanly when the visited set changes between turns.
    e0 = str(e["src"]);
    e1 = str(e["tgt"]);
    is_active = (e0 in visited) and (e1 in visited);
    if not is_active {
        return <g/>;
    }
    src_list = [n for n in graph_nodes if str(n["id"]) == e0];
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if (not src_list) or (not tgt_list) {
        return <g/>;
    }
    src = src_list[0];
    tgt = tgt_list[0];
    beam_color = edgeWalkerColor(e0, e1);
    return
        <circle
            key={"dot-" + e0 + "-" + e1}
            r="2.5"
            fill={beam_color}
            opacity="0.95"
            style={{"filter": "drop-shadow(0 0 4px " + beam_color + ")"}}
        >
            <animate
                attributeName="cx"
                from={str(src["x"])}
                to={str(tgt["x"])}
                dur="1.8s"
                repeatCount="indefinite"
            />
            <animate
                attributeName="cy"
                from={str(src["y"])}
                to={str(tgt["y"])}
                dur="1.8s"
                repeatCount="indefinite"
            />
        </circle>;
}

impl GraphViz.renderEdgeBeam(e: dict) -> JsxElement {
    # Magic UI style "beam sweep" — a CSS-animated dashed line laid on top
    # of the static edge, colored by the owning walker. The dashoffset
    # animation creates a clean wave traveling source→target without
    # SMIL's accumulation issues across re-renders.
    e0 = str(e["src"]);
    e1 = str(e["tgt"]);
    is_active = (e0 in visited) and (e1 in visited);
    if not is_active {
        return <g/>;
    }
    src_list = [n for n in graph_nodes if str(n["id"]) == e0];
    tgt_list = [n for n in graph_nodes if str(n["id"]) == e1];
    if (not src_list) or (not tgt_list) {
        return <g/>;
    }
    src = src_list[0];
    tgt = tgt_list[0];
    beam_color = edgeWalkerColor(e0, e1);
    return
        <line
            key={"beam-" + e0 + "-" + e1}
            className="lp-beam-sweep"
            x1={str(src["x"])}
            y1={str(src["y"])}
            x2={str(tgt["x"])}
            y2={str(tgt["y"])}
            stroke={beam_color}
            strokeWidth="2.2"
            strokeLinecap="round"
            strokeDasharray="14 86"
            opacity="0.85"
            style={{"filter": "drop-shadow(0 0 3px " + beam_color + ")"}}
        />;
}

impl GraphViz.renderTooltip -> JsxElement {
    n_match = [n for n in graph_nodes if str(n["id"]) == hovered_node];
    if not n_match {
        return <span/>;
    }
    n: Any = n_match[0];
    nx = int(n["x"]);
    ny = int(n["y"]);
    color = nodeColor(str(n["type"]));
    walker_name = str(n["walker"]) if n["walker"] else "—";
    tip = str(n["tooltip"]) if n["tooltip"] else "";
    # Position relative to the SVG viewBox (680 wide / 570 tall). The
    # parent div is `position: relative`, so left/top are percent of the
    # rendered SVG box.
    left_pct = (nx * 100.0) / 680.0;
    top_pct = ((ny + 36) * 100.0) / 570.0;
    return
        <div
            style={{
                "position": "absolute",
                "left": str(left_pct) + "%",
                "top": str(top_pct) + "%",
                "transform": "translate(-50%, 0)",
                "maxWidth": "240px",
                "padding": "8px 10px",
                "background": "rgba(10,10,10,0.96)",
                "border": "0.5px solid " + color + "55",
                "borderLeft": "2px solid " + color,
                "borderRadius": "8px",
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.85)",
                "lineHeight": "1.45",
                "pointerEvents": "none",
                "zIndex": "20",
                "boxShadow": "0 6px 18px rgba(0,0,0,0.4)"
            }}
        >
            <div style={{"fontSize": "9px", "color": color, "textTransform": "uppercase", "letterSpacing": "0.08em", "fontWeight": "600", "marginBottom": "3px"}}>
                {str(n["type"]) + " · " + walker_name}
            </div>
            <div>{tip}</div>
        </div>;
}

impl GraphViz.renderNode(n: dict) -> JsxElement {
    nid = str(n["id"]);
    is_visited = nid in visited;
    is_current = nid == current;
    is_hovered = nid == hovered_node;
    color = nodeColor(str(n["type"]));
    return
        <g
            key={nid}
            transform={"translate(" + str(n["x"]) + "," + str(n["y"]) + ")"}
            onMouseEnter={lambda _e: MouseEvent { hovered_node = nid; }}
            onMouseLeave={lambda _e: MouseEvent { hovered_node = ""; }}
            style={{"cursor": "pointer"}}
        >
            {(is_current or is_hovered) and <circle
                r="22"
                fill="none"
                stroke={color}
                strokeWidth="1.5"
                opacity={("0.5" if is_hovered else "0.35")}
            />}
            <circle
                r={("15" if is_hovered else "13")}
                fill={(color if is_visited else "rgba(255,255,255,0.04)")}
                stroke={color}
                strokeWidth={("2" if (is_current or is_hovered) else "0.8")}
                opacity={("1" if is_visited else ("0.7" if is_hovered else "0.35"))}
                style={{"transition": "all 0.4s ease"}}
            />
            <text
                y="26"
                textAnchor="middle"
                fill={(color if (is_visited or is_hovered) else "rgba(255,255,255,0.25)")}
                fontSize="9"
                fontWeight={("600" if (is_current or is_hovered) else "400")}
                style={{"transition": "all 0.4s ease", "pointerEvents": "none"}}
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
