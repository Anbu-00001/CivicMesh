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

impl GraphViz.startReplay -> None {
    is_playing = True;
    visited = [];
    current = "";
    replay_idx = 0;
    stepReplay(0);
}

impl GraphViz.stepReplay(idx: int) -> None {
    # The idx is passed as a parameter (not read from React state) so that
    # each setTimeout-scheduled recursive call advances correctly even when
    # the function closure was captured from an older render. React state
    # setters still work from stale closures — they update the latest state.
    if idx >= len(walk_path) {
        is_playing = False;
        current = "";
        return;
    }
    current = walk_path[idx];
    visited = walk_path[:idx + 1];
    replay_idx = idx + 1;
    if (idx + 1) < len(walk_path) {
        setTimeout(lambda { stepReplay(idx + 1); }, 500);
    } else {
        setTimeout(lambda { is_playing = False; current = ""; }, 500);
    }
}
