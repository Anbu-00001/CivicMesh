"""GraphViz implementation: snapshot load, layered layout, replay, rendering."""

impl GraphViz.loadSnap -> None {
    if not user_id { return; }
    loading = True;
    res = await jacSpawn("GraphSnapshotWalker", "", {"user_id": user_id}).catch(
        lambda e: Any -> dict { return {"reports": [], "spawn_error": str(e)}; }
    );
    reps = res["reports"];
    if reps and len(reps) > 0 {
        snap = reps[len(reps) - 1];
        err = "";
    } elif res["spawn_error"] {
        err = str(res["spawn_error"]);
    }
    loading = False;
}

impl GraphViz.layout -> dict {
    # Layered layout: one row per node type; rules and forms sit under their
    # program. Returns {id: [x, y]} as a plain object.
    pos: dict = {};
    if not snap or not snap["nodes"] { return pos; }
    nodes: list = list(snap["nodes"]);
    apps: list = [];
    mids: list = [];
    ins: list = [];
    res: list = [];
    routes: list = [];
    for n in nodes {
        t = str(n["type"]);
        if t == "Root" { pos["root"] = [GV_W / 2, GV_ROW_Y["Root"]]; }
        elif t == "PersonNode" { pos[str(n["id"])] = [GV_W / 2, GV_ROW_Y["PersonNode"]]; }
        elif t == "ApplicationNode" { apps.append(n); }
        elif t == "NeedNode" { mids.append(n); }
        elif t == "SessionInsight" { ins.append(n); }
        elif t == "ResourceNode" {
            if n["route"] { routes.append(n); } else { res.append(n); }
        }
    }
    row2: list = apps + mids + ins;
    k = len(row2);
    for i in range(k) {
        pos[str(row2[i]["id"])] = [GV_W * (i + 1) / (k + 1), GV_ROW_Y["NeedNode"]];
    }
    row3: list = res + routes;
    m = len(row3);
    for j in range(m) {
        pos[str(row3[j]["id"])] = [GV_W * (j + 1) / (m + 1), GV_ROW_Y["ResourceNode"]];
    }
    for n in nodes {
        t = str(n["type"]);
        if (t == "EligibilityRuleNode" or t == "FormNode") and n["parent"] and pos[str(n["parent"])] {
            pos[str(n["id"])] = [pos[str(n["parent"])][0], GV_ROW_Y[t]];
        }
    }
    return pos;
}

impl GraphViz.replayOrder -> list {
    # The order the walkers touch the graph in one turn.
    if not snap or not snap["nodes"] { return []; }
    nodes: list = list(snap["nodes"]);
    order: list = ["root", "person", "need"];
    for t in ["ResourceNode", "EligibilityRuleNode", "FormNode", "ApplicationNode", "SessionInsight"] {
        for n in nodes {
            if str(n["type"]) == t and not n["route"] { order.append(str(n["id"])); }
        }
    }
    for n in nodes {
        if n["route"] { order.append(str(n["id"])); }
    }
    return order;
}

impl GraphViz.startReplay -> None {
    order = replayOrder();
    if len(order) == 0 { return; }
    playing = True;
    visited = [];
    stepReplay(0, order);
}

impl GraphViz.stepReplay(idx: int, order: list) -> None {
    if idx >= len(order) {
        current = "";
        playing = False;
        return;
    }
    current = str(order[idx]);
    visited = order.slice(0, idx + 1);
    setTimeout(lambda { stepReplay(idx + 1, order); }, 320);
}

impl GraphViz.renderEdge(e: Any, pos: Any, i: int) -> JsxElement {
    a = pos[str(e["src"])];
    b = pos[str(e["tgt"])];
    if not a or not b { return <g key={"e" + str(i)}/>; }
    lit = playing and visited.includes(str(e["src"])) and visited.includes(str(e["tgt"]));
    focus = hovered == str(e["src"]) or hovered == str(e["tgt"]) or selected == str(e["src"]) or selected == str(e["tgt"]);
    color = "rgba(255,255,255,0.16)";
    if e["tier"] { color = GV_TIER[str(e["tier"])] if GV_TIER[str(e["tier"])] else color; }
    if e["route"] { color = "#FFE500"; }
    mx = (Number(a[0]) + Number(b[0])) / 2;
    my = (Number(a[1]) + Number(b[1])) / 2;
    # Edges between nodes on the same row (leads_to routes) arc below the row
    # instead of running straight through the programs in between.
    same_row = Math.abs(Number(a[1]) - Number(b[1])) < 4;
    dx = Math.abs(Number(b[0]) - Number(a[0]));
    cy = Number(a[1]) + 26 + dx * 0.12;
    d = ("M " + str(a[0]) + " " + str(a[1]) + " Q " + str(mx) + " " + str(cy) + " " + str(b[0]) + " " + str(b[1])) if same_row else ("M " + str(a[0]) + " " + str(a[1]) + " L " + str(b[0]) + " " + str(b[1]));
    if same_row { my = (Number(a[1]) + cy) / 2 + 8; }
    return
        <g key={"e" + str(i)}>
            <path
                d={d}
                fill="none"
                stroke={color}
                strokeWidth={("2.4" if (lit or focus) else "1.2")}
                strokeOpacity={("1" if (lit or focus or e["tier"] or e["route"]) else "0.8")}
                strokeDasharray={("5 4" if (e["route"] or e["dashed"]) else "")}
            />
            {(show_labels or focus) and <text x={mx} y={my - 4} className="gv-edge-label" textAnchor="middle">{str(e["label"])}</text>}
        </g>;
}

impl GraphViz.renderNode(n: Any, pos: Any) -> JsxElement {
    nid = str(n["id"]);
    p = pos[nid];
    if not p { return <g key={nid}/>; }
    t = str(n["type"]);
    fill = GV_COLORS[t] if GV_COLORS[t] else "#888";
    r = 17 if t == "ResourceNode" else (14 if (t == "PersonNode" or t == "NeedNode") else 11);
    ring = GV_TIER[str(n["tier"])] if n["tier"] else "";
    is_cur = current == nid;
    was = visited.includes(nid);
    dim = (playing and not was) or n["dim"];
    sub = "";
    if n["p"] { sub = str(Math.round(Number(n["p"]) * 100)) + "%"; }
    elif n["sub"] { sub = str(n["sub"]); }
    return
        <g
            key={nid}
            className="gv-node"
            style={{"opacity": ("0.35" if dim else "1"), "cursor": "pointer"}}
            onMouseEnter={lambda _e: MouseEvent { hovered = nid; }}
            onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
            onClick={lambda _e: MouseEvent { selected = ("" if selected == nid else nid); }}
        >
            {is_cur and <circle cx={p[0]} cy={p[1]} r={r + 9} fill="none" stroke="#FFE500" strokeWidth="2" className="gv-pulse"/>}
            {ring and <circle cx={p[0]} cy={p[1]} r={r + 4} fill="none" stroke={ring} strokeWidth="2.5"/>}
            <circle
                cx={p[0]} cy={p[1]} r={r}
                fill={fill} fillOpacity={("0.35" if n["route"] else "0.9")}
                stroke={("#FFFFFF" if selected == nid else "rgba(0,0,0,0.35)")}
                strokeWidth={("2" if selected == nid else "1")}
                strokeDasharray={("4 3" if n["route"] else "")}
            />
            <text x={p[0]} y={Number(p[1]) + r + 13} className="gv-label" textAnchor="middle">{(str(n["label"]).slice(0, 11) + "…") if len(str(n["label"])) > 12 else str(n["label"])}</text>
            {sub and <text x={p[0]} y={Number(p[1]) + r + 25} className="gv-sub-label" textAnchor="middle">{sub}</text>}
        </g>;
}

impl GraphViz.renderDetail(pos: Any) -> JsxElement {
    nid = hovered if hovered else selected;
    picked: Any = None;
    if snap and snap["nodes"] {
        for n in list(snap["nodes"]) {
            if str(n["id"]) == nid { picked = n; }
        }
    }
    if not picked {
        return
            <div className="gv-detail cm-muted">
                Hover or tap a node. Program rings show the engine's verdict for your latest need; the percentage is P(eligible).
            </div>;
    }
    t = str(picked["type"]);
    return
        <div className="gv-detail">
            <div className="gv-detail-type" style={{"color": GV_COLORS[t]}}>{t}</div>
            <div className="gv-detail-title">{str(picked["label"])}</div>
            <div className="gv-detail-tip">{str(picked["tip"])}</div>
        </div>;
}
