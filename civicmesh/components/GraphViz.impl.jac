"""GraphViz implementation: snapshot load, view model, replay, rendering."""

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

impl GraphViz.model -> dict {
    # View model over the snapshot: which card each node becomes, the y of
    # every connector endpoint, and what the focused card is related to.
    # Indexes are stored 1-based so 0 never reads as "missing".
    m: dict = {
        "progs": [], "routes": [], "idx": {}, "ys": [], "apps": [], "app_for": {}, "linked": {},
        "kids": {}, "arcs": [], "outs": [], "person": None, "need": None, "prev": None,
        "insights": None, "byid": {}, "ry": {}, "rtop": {}, "stray": [], "rel": {}, "h": 0, "need_y": 0, "links": []
    };
    if not snap or not snap["nodes"] { return m; }
    for n in list(snap["nodes"]) {
        nid = str(n["id"]);
        t = str(n["type"]);
        m["byid"][nid] = n;
        if t == "PersonNode" { m["person"] = n; }
        elif t == "NeedNode" {
            if nid == "need" { m["need"] = n; } else { m["prev"] = n; }
        } elif t == "SessionInsight" { m["insights"] = n; }
        elif t == "ApplicationNode" { m["apps"].append(n); }
        elif t == "ResourceNode" {
            if n["route"] { m["routes"].append(n); }
            else {
                m["progs"].append(n);
                m["idx"][nid] = len(m["progs"]);
            }
        } elif (t == "EligibilityRuleNode" or t == "FormNode") and n["parent"] {
            key = str(n["parent"]);
            if not m["kids"][key] { m["kids"][key] = {}; }
            m["kids"][key][("rule" if t == "EligibilityRuleNode" else "form")] = n;
        }
    }
    for e in list(snap["edges"]) {
        s = str(e["src"]);
        g = str(e["tgt"]);
        if e["route"] {
            parts = str(e["label"]).split(" · ");
            r = {"src": s, "tgt": g, "days": (parts[1] if len(parts) > 1 else ""), "diff": (parts[2] if len(parts) > 2 else "")};
            if m["idx"][g] and m["idx"][s] { m["arcs"].append(r); m["links"].append(r); }
            elif m["idx"][s] { m["outs"].append(r); m["links"].append(r); }
        } elif str(e["label"]) == "for" {
            m["app_for"][g] = m["byid"][s];
            m["linked"][s] = True;
        }
    }
    n_p = len(m["progs"]);
    for i in range(n_p) {
        m["ys"].append(GV_PAD + i * (GV_CH + GV_GAP) + GV_CH / 2);
    }
    m["need_y"] = GV_PAD + GV_YOU_H + GV_GAP + GV_NEED_H / 2;
    # Route cards sit at the mean height of the programs that lead to them,
    # pushed apart so they never overlap (a one-layer barycenter pass — the
    # crossing-reduction step of a Sugiyama layout).
    want: list = [];
    for r in m["routes"] {
        rid = str(r["id"]);
        tot = 0;
        cnt = 0;
        for o in m["outs"] {
            if o["tgt"] == rid {
                tot = tot + m["ys"][m["idx"][o["src"]] - 1];
                cnt = cnt + 1;
            }
        }
        want.append([rid, (tot / cnt if cnt > 0 else GV_PAD + GV_RH / 2)]);
    }
    for a in range(1, len(want)) {
        k = a;
        while k > 0 and want[k - 1][1] > want[k][1] {
            tmp = want[k - 1];
            want[k - 1] = want[k];
            want[k] = tmp;
            k = k - 1;
        }
    }
    bottom = GV_PAD - GV_GAP;
    for w in want {
        top = Math.max(w[1] - GV_RH / 2, bottom + GV_GAP);
        m["rtop"][w[0]] = top;
        m["ry"][w[0]] = top + GV_RH / 2;
        bottom = top + GV_RH;
    }
    m["h"] = Math.max(GV_PAD + n_p * (GV_CH + GV_GAP) - GV_GAP + GV_PAD, bottom + GV_PAD, GV_PAD + GV_YOU_H + GV_GAP + GV_NEED_H + GV_PAD);
    for a in m["apps"] {
        if not m["linked"][str(a["id"])] { m["stray"].append(a); }
    }
    fid = hovered if hovered else selected;
    if fid {
        m["rel"][fid] = True;
        if fid == "need" or fid == "person" {
            for p in m["progs"] { m["rel"][str(p["id"])] = True; }
        }
        for r in m["links"] {
            if r["src"] == fid or r["tgt"] == fid {
                m["rel"][r["src"]] = True;
                m["rel"][r["tgt"]] = True;
            }
        }
    }
    return m;
}

impl GraphViz.replayOrder -> list {
    # The order the walkers touch the graph in one turn; "routes" is the
    # Pathfinder step that draws the leads_to arrows.
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
    order.append("routes");
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
    setTimeout(lambda { stepReplay(idx + 1, order); }, 300);
}

impl GraphViz.isOn(nid: str) -> bool {
    return (not playing) or visited.includes(nid);
}

impl GraphViz.pick(nid: str) -> None {
    selected = ("" if selected == nid else nid);
}

impl GraphViz.renderLeft(m: dict) -> JsxElement {
    p = m["person"];
    nd = m["need"];
    ptip = "";
    if p {
        pp: list = str(p["tip"]).replace("PersonNode · ", "").split(" · ");
        ptip = " · ".join([(str(x).replace("language ", "").toUpperCase() if str(x).startsWith("language ") else str(x)) for x in pp]);
    }
    quote = "";
    if nd and str(nd["tip"]).includes(" — ") {
        quote = str(nd["tip"]).split(" — ").slice(1).join(" — ");
    }
    fid = hovered if hovered else selected;
    extras: list = [];
    if m["prev"] {
        extras.append(["needs_prev", str(m["prev"]["label"]) + " need" + ("" if str(m["prev"]["label"]) == "+1 earlier" else "s"), "has_need"]);
    }
    for a in m["stray"] {
        extras.append([str(a["id"]), "Tracking: " + str(a["label"]) + " · " + str(a["sub"]), "applied_to"]);
    }
    if m["insights"] {
        extras.append(["insights", str(m["insights"]["label"]).replace("×", "") + " self-critique" + ("" if str(m["insights"]["label"]) == "×1" else "s") + " of this chat", "reflected_on"]);
    }
    return
        <div className="gv-col gv-col-left">
            <div className="gv-colhead">{"1 · You"}</div>
            <div className="gv-stack-left">
                <button
                    type="button"
                    className={"gv-you" + (" gv-sel" if selected == "person" else "") + (" gv-cur" if (current == "person" or current == "root") else "") + ("" if isOn("person") else " gv-off")}
                    onMouseEnter={lambda _e: MouseEvent { hovered = "person"; }}
                    onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
                    onFocus={lambda _e: Any { hovered = "person"; }}
                    onBlur={lambda _e: Any { hovered = ""; }}
                    onClick={lambda _e: MouseEvent { pick("person"); }}
                    aria-label={"You — " + ptip}
                >
                    <span className="gv-avatar" aria-hidden="true"><svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="5" r="3" fill="#111"/><path d="M 2 15 C 2 10.5, 14 10.5, 14 15 z" fill="#111"/></svg></span>
                    <span className="gv-you-text">
                        <span className="gv-you-name">You{schema and <span className="gv-schema">{" PersonNode ← root·owns"}</span>}</span>
                        <span className="gv-you-sub">{ptip}</span>
                    </span>
                </button>
                <div className="gv-stem" aria-hidden="true"/>
                {nd and <button
                    type="button"
                    className={"gv-need" + (" gv-sel" if selected == "need" else "") + (" gv-hot" if fid == "need" else "") + (" gv-cur" if current == "need" else "") + ("" if isOn("need") else " gv-off")}
                    onMouseEnter={lambda _e: MouseEvent { hovered = "need"; }}
                    onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
                    onFocus={lambda _e: Any { hovered = "need"; }}
                    onBlur={lambda _e: Any { hovered = ""; }}
                    onClick={lambda _e: MouseEvent { pick("need"); }}
                    aria-label={"Latest need: " + str(nd["label"]) + ", " + str(nd["sub"])}
                >
                    <span className="gv-need-cap">{("NeedNode · has_need" if schema else "Latest need")}</span>
                    <span className="gv-need-cat">{str(nd["label"])}<span className="gv-urg">{str(nd["sub"])}</span></span>
                    {quote and <span className="gv-need-quote">{quote}</span>}
                </button>}
                {len(extras) > 0 and <div className="gv-extras">
                    {[<button
                        key={x[0]}
                        type="button"
                        className={"gv-extra" + (" gv-sel" if selected == x[0] else "") + (" gv-cur" if current == x[0] else "") + ("" if isOn(x[0]) else " gv-off")}
                        onMouseEnter={lambda _e: MouseEvent { hovered = x[0]; }}
                        onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
                        onFocus={lambda _e: Any { hovered = x[0]; }}
                        onBlur={lambda _e: Any { hovered = ""; }}
                        onClick={lambda _e: MouseEvent { pick(x[0]); }}
                    >{x[1]}{schema and <span className="gv-schema">{" " + x[2]}</span>}</button> for x in extras]}
                </div>}
            </div>
        </div>;
}

impl GraphViz.renderCard(n: Any, i: int, m: dict) -> JsxElement {
    nid = str(n["id"]);
    ti = GV_TIER[str(n["tier"])] if GV_TIER[str(n["tier"])] else GV_TIER["unlikely"];
    pct = Math.round(Number(n["p"]) * 100);
    full = str(n["tip"]).split(" · ")[0];
    head = full;
    tail = "";
    if full.includes("(") and full.includes(")") {
        head = full.split("(")[0].trim();
        tail = full.split("(")[1].split(")")[0];
    }
    kids: Any = m["kids"][nid] if m["kids"][nid] else {};
    rule = kids["rule"];
    form = kids["form"];
    fparts: list = str(form["tip"]).split(" · ") if form else [];
    mins = str(fparts[1]) if len(fparts) > 1 else "";
    if mins == "0 min" { mins = "none needed"; }
    app = m["app_for"][nid];
    leads: list = [];
    for r in m["links"] {
        if r["src"] == nid {
            tgt = m["byid"][r["tgt"]];
            leads.append((str(tgt["label"]) if tgt else "?") + " · " + str(r["days"]));
        }
    }
    fid = hovered if hovered else selected;
    faded = fid and fid != nid and not m["rel"][nid];
    cls = "gv-card" + (" gv-sel" if selected == nid else "") + (" gv-hot" if fid == nid else "") + (" gv-faded" if faded else "") + (" gv-cur" if current == nid else "") + ("" if isOn(nid) else " gv-off");
    return
        <button
            key={nid}
            type="button"
            className={cls}
            style={{"--tier": ti["color"]}}
            onMouseEnter={lambda _e: MouseEvent { hovered = nid; }}
            onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
            onFocus={lambda _e: Any { hovered = nid; }}
            onBlur={lambda _e: Any { hovered = ""; }}
            onClick={lambda _e: MouseEvent { pick(nid); }}
            aria-label={full + ": " + ti["label"] + ", " + str(pct) + " percent likely eligible" + (", application " + str(app["sub"]) if app else "")}
        >
            <span className="gv-card-top">
                <span className="gv-tier"><span className="gv-tier-ico" aria-hidden="true">{ti["icon"]}</span>{ti["label"]}</span>
                {(app and isOn(str(app["id"]))) and <span className="gv-app">{"Applied · " + str(app["sub"])}</span>}
                <span className="gv-pct">{(("eligible_for p=" + str(Number(n["p"]).toFixed(2))) if schema else (str(pct) + "%"))}</span>
            </span>
            <span className="gv-card-name"><b>{head}</b>{tail and <span>{tail}</span>}</span>
            <span className="gv-meter" aria-hidden="true"><span style={{"width": str(pct) + "%"}}/></span>
            <span className="gv-card-meta">
                {rule and <span className={"gv-leaf" + (" gv-leaf-cur" if current == str(rule["id"]) else "") + ("" if isOn(str(rule["id"])) else " gv-leaf-off")}>{("EligibilityRuleNode" if schema else "rule")}</span>}
                {form and <span className={"gv-leaf" + (" gv-leaf-cur" if current == str(form["id"]) else "") + ("" if isOn(str(form["id"])) else " gv-leaf-off")}>{("FormNode" if schema else "form") + (" · " + mins if mins else "")}</span>}
            </span>
            {len(leads) > 0 and <span className="gv-leads">{"→ leads to " + ", ".join(leads)}</span>}
        </button>;
}

impl GraphViz.renderRight(m: dict) -> JsxElement {
    fid = hovered if hovered else selected;
    return
        <div className="gv-col gv-col-right">
            <div className="gv-colhead">{"3 · Where they lead"}</div>
            <div className="gv-rstack" style={{"height": str(m["h"]) + "px"}}>
                {[<button
                    key={str(r["id"])}
                    type="button"
                    className={"gv-rcard" + (" gv-sel" if selected == str(r["id"]) else "") + (" gv-hot" if fid == str(r["id"]) else "") + (" gv-faded" if (fid and fid != str(r["id"]) and not m["rel"][str(r["id"])]) else "") + (" gv-cur" if current == str(r["id"]) else "") + ("" if isOn(str(r["id"])) else " gv-off")}
                    style={{"top": str(m["rtop"][str(r["id"])]) + "px"}}
                    onMouseEnter={lambda _e: MouseEvent { hovered = str(r["id"]); }}
                    onMouseLeave={lambda _e: MouseEvent { hovered = ""; }}
                    onFocus={lambda _e: Any { hovered = str(r["id"]); }}
                    onBlur={lambda _e: Any { hovered = ""; }}
                    onClick={lambda _e: MouseEvent { pick(str(r["id"])); }}
                    aria-label={str(r["tip"])}
                >
                    <span className="gv-rcard-cap">{("ResourceNode · leads_to" if schema else "Later")}</span>
                    <span className="gv-rcard-name"><b>{str(r["tip"]).split(" · ")[0].split("(")[0].trim()}</b>{str(r["tip"]).split(" · ")[0].includes("(") and <span>{str(r["tip"]).split(" · ")[0].split("(")[1].split(")")[0]}</span>}</span>
                    <span className="gv-rcard-sub">{"via " + ", ".join([(str(m["byid"][o["src"]]["label"]) + " · " + str(o["days"])) for o in m["outs"] if o["tgt"] == str(r["id"])])}</span>
                </button> for r in m["routes"]]}
            </div>
        </div>;
}

impl GraphViz.renderFan(m: dict) -> JsxElement {
    # need → program: one smooth curve per eligible_for edge; thickness is
    # P(eligible), color the verdict. Focusing a card fades the others.
    h = m["h"];
    sy = m["need_y"];
    w = GV_GL;
    fid = hovered if hovered else selected;
    paths: list = [];
    for i in range(len(m["progs"])) {
        n = m["progs"][i];
        nid = str(n["id"]);
        if not isOn(nid) { continue; }
        ti = GV_TIER[str(n["tier"])] if GV_TIER[str(n["tier"])] else GV_TIER["unlikely"];
        y = m["ys"][i];
        hot = fid == nid or fid == "need" or fid == "person";
        faded = fid and not hot;
        d = "M 0 " + str(sy) + " C " + str(w * 0.55) + " " + str(sy) + ", " + str(w * 0.45) + " " + str(y) + ", " + str(w) + " " + str(y);
        paths.append(
            <path
                key={"f" + str(i)}
                d={d}
                fill="none"
                stroke={ti["color"]}
                strokeWidth={str(1.2 + 3.2 * Number(n["p"]))}
                strokeOpacity={("0.95" if hot else ("0.12" if faded else "0.5"))}
                strokeLinecap="round"
                pathLength="1"
                className={("gv-line gv-draw" if (playing and current == nid) else "gv-line")}
            />
        );
    }
    return
        <svg className="gv-gutter" width={w} height={h} viewBox={"0 0 " + str(w) + " " + str(h)} aria-hidden="true">
            {paths}
            {(m["need"] and isOn("need")) and <circle cx="0" cy={sy} r="3.5" fill="#FFE500"/>}
        </svg>;
}

impl GraphViz.renderRoutes(m: dict) -> JsxElement {
    # leads_to: an arrow leaves a program's upper half and enters the target's
    # lower half. Between two programs on screen it arcs out along the right
    # edge (further out for longer spans, so arcs nest instead of crossing);
    # to a program not scored for this need it runs to the "Later" column.
    h = m["h"];
    w = GV_GR if len(m["routes"]) > 0 else (64 if len(m["arcs"]) > 0 else 12);
    fid = hovered if hovered else selected;
    items: list = [];
    k = 0;
    for r in m["arcs"] {
        k = k + 1;
        if not isOn("routes") { continue; }
        i = m["idx"][r["src"]] - 1;
        j = m["idx"][r["tgt"]] - 1;
        y1 = m["ys"][i] - 9;
        y2 = m["ys"][j] + 9;
        b = Math.min(w - 12, 18 + 13 * Math.abs(i - j));
        hot = fid == r["src"] or fid == r["tgt"];
        faded = fid and not hot;
        items.append(
            <g key={"a" + str(k)}>
                <path
                    d={"M 1 " + str(y1) + " C " + str(b) + " " + str(y1) + ", " + str(b) + " " + str(y2) + ", 5 " + str(y2)}
                    fill="none"
                    stroke={("#FFFFFF" if hot else "rgba(255,255,255,0.55)")}
                    strokeWidth={("1.8" if hot else "1.2")}
                    strokeOpacity={("0.95" if hot else ("0.15" if faded else "0.6"))}
                    markerEnd={("url(#gv-arr-hot)" if hot else "url(#gv-arr)")}
                    pathLength="1"
                    className={("gv-line gv-draw" if (playing and current == "routes") else "gv-line")}
                />
                {hot and <text x={str(b * 0.75 + 5)} y={str((y1 + y2) / 2 + 3)} className="gv-arc-label">{str(r["days"])}</text>}
            </g>
        );
    }
    for r in m["outs"] {
        k = k + 1;
        if not isOn(r["tgt"]) { continue; }
        i = m["idx"][r["src"]] - 1;
        y1 = m["ys"][i] - 9;
        y2 = m["ry"][r["tgt"]];
        hot = fid == r["src"] or fid == r["tgt"];
        faded = fid and not hot;
        items.append(
            <path
                key={"o" + str(k)}
                d={"M 1 " + str(y1) + " C " + str(w * 0.5) + " " + str(y1) + ", " + str(w * 0.5) + " " + str(y2) + ", " + str(w - 5) + " " + str(y2)}
                fill="none"
                stroke={("#FFFFFF" if hot else "rgba(255,255,255,0.55)")}
                strokeWidth={("1.8" if hot else "1.2")}
                strokeOpacity={("0.95" if hot else ("0.15" if faded else "0.6"))}
                markerEnd={("url(#gv-arr-hot)" if hot else "url(#gv-arr)")}
                pathLength="1"
                className={("gv-line gv-draw" if (playing and current == r["tgt"]) else "gv-line")}
            />
        );
    }
    return
        <svg className="gv-gutter" width={w} height={h} viewBox={"0 0 " + str(w) + " " + str(h)} aria-hidden="true">
            <defs>
                <marker id="gv-arr" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M 0 0 L 8 4 L 0 8 z" fill="rgba(255,255,255,0.6)"/></marker>
                <marker id="gv-arr-hot" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto"><path d="M 0 0 L 8 4 L 0 8 z" fill="#FFFFFF"/></marker>
            </defs>
            {items}
        </svg>;
}

impl GraphViz.renderDetail(m: dict) -> JsxElement {
    nid = hovered if hovered else selected;
    picked: Any = m["byid"][nid] if nid else None;
    if not picked {
        return
            <div className="gv-detail cm-muted">
                Hover, tap or tab to a card. Each program card shows the engine's verdict for your latest need and P(eligible); its rule and form are the program's EligibilityRuleNode and FormNode.
            </div>;
    }
    t = str(picked["type"]);
    kind = {"PersonNode": "You", "NeedNode": "Need", "ResourceNode": ("Later route" if picked["route"] else "Program"), "ApplicationNode": "Application you're tracking", "SessionInsight": "Self-critique", "EligibilityRuleNode": "Rule", "FormNode": "Form"}[t];
    parts: list = str(picked["tip"]).split(" · ");
    title = str(picked["label"]);
    body = str(picked["tip"]);
    if t == "ResourceNode" {
        title = str(parts[0]);
        body = " · ".join(parts.slice((3 if picked["tier"] else 1)));
    }
    kids: Any = m["kids"][nid] if m["kids"][nid] else {};
    app = m["app_for"][nid];
    ti = GV_TIER[str(picked["tier"])] if picked["tier"] else None;
    edges: list = [];
    if schema and snap and snap["edges"] {
        for e in list(snap["edges"]) {
            if str(e["src"]) == nid or str(e["tgt"]) == nid {
                a = m["byid"][str(e["src"])];
                b = m["byid"][str(e["tgt"])];
                edges.append((str(a["label"]) if a else str(e["src"])) + " —" + str(e["label"]) + "→ " + (str(b["label"]) if b else str(e["tgt"])));
            }
        }
    }
    leads: list = [];
    for r in m["links"] {
        if r["src"] == nid {
            tg = m["byid"][r["tgt"]];
            dd = str(r["days"]).replace("d", "");
            leads.append((str(tg["tip"]).split(" · ")[0] if tg else "?") + " — typically " + dd + (" day" if dd == "1" else " days") + ", " + str(r["diff"]));
        }
    }
    return
        <div className="gv-detail">
            <div className="gv-detail-type" style={{"color": (ti["color"] if ti else "rgba(255,255,255,0.55)")}}>{kind + (" · " + t if schema else "")}</div>
            <div className="gv-detail-title">{title}</div>
            {ti and <div className="gv-detail-tier" style={{"--tier": ti["color"]}}><span className="gv-tier-ico">{ti["icon"]}</span>{ti["label"] + " · P(eligible) " + str(Math.round(Number(picked["p"]) * 100)) + "%"}</div>}
            <div className="gv-detail-tip">{body}</div>
            {kids["rule"] and <div className="gv-kv"><span>Rule</span><div>{str(kids["rule"]["tip"])}</div></div>}
            {kids["form"] and <div className="gv-kv"><span>Form</span><div>{(str(kids["form"]["tip"]).slice(0, -3) if str(kids["form"]["tip"]).endsWith(" · ") else str(kids["form"]["tip"])).replace(" · 0 min", "")}</div></div>}
            {app and <div className="gv-kv"><span>Applied</span><div>{str(app["sub"]) + " — " + str(app["tip"]).split(" · ").slice(-1)[0]}</div></div>}
            {len(leads) > 0 and <div className="gv-kv"><span>Leads to</span><div>{[<div key={"l" + str(q)}>{leads[q]}</div> for q in range(len(leads))]}</div></div>}
            {len(edges) > 0 and <div className="gv-kv gv-kv-mono"><span>Edges</span><div>{[<div key={"e" + str(q)}>{edges[q]}</div> for q in range(len(edges))]}</div></div>}
        </div>;
}

impl GraphViz.renderLegend -> JsxElement {
    return
        <div className="gv-legend">
            <div className="gv-legend-title">How to read it</div>
            <div className="gv-legend-tiers">
                {[<span key={k} className="gv-tier" style={{"--tier": GV_TIER[k]["color"]}}><span className="gv-tier-ico" aria-hidden="true">{GV_TIER[k]["icon"]}</span>{GV_TIER[k]["label"]}</span> for k in GV_TIER_ORDER]}
            </div>
            <div className="gv-legend-row"><svg width="30" height="12" aria-hidden="true"><path d="M 1 3 C 12 3, 16 9, 29 9" stroke="rgba(255,255,255,0.7)" strokeWidth="3.4" fill="none" strokeLinecap="round"/></svg><span>thicker line = more likely eligible</span></div>
            <div className="gv-legend-row"><svg width="30" height="12" aria-hidden="true"><path d="M 1 6 L 25 6" stroke="rgba(255,255,255,0.7)" strokeWidth="1.3" fill="none"/><path d="M 23 2.5 L 29 6 L 23 9.5 z" fill="rgba(255,255,255,0.7)"/></svg><span>leads to — a program this one often opens up</span></div>
            <div className="gv-legend-row"><span className="gv-app">Applied</span><span>an application you're tracking</span></div>
            <div className="gv-legend-row"><span className="gv-leaf">rule</span><span className="gv-leaf">form</span><span>the program's criteria and form</span></div>
            <div className="gv-legend-row"><span className="gv-legend-hollow"/><span>outlined = not scored for this need yet</span></div>
        </div>;
}
