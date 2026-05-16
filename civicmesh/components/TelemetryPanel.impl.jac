"""Render helpers for TelemetryPanel."""

impl TelemetryPanel.renderMetric(m: tuple) -> JsxElement {
    return
        <div
            key={m[2]}
            className="stat-enter"
            style={{
                "padding": "14px",
                "background": "rgba(255,255,255,0.03)",
                "backdropFilter": "blur(12px)",
                "border": "0.5px solid rgba(255,255,255,0.07)",
                "borderRadius": "12px",
                "textAlign": "center"
            }}
        >
            <div style={{"fontSize": "20px", "marginBottom": "5px"}}>{m[0]}</div>
            <div style={{"fontSize": "20px", "fontWeight": "600", "color": "#FFE500"}}>{m[1]}</div>
            <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.35)", "marginTop": "3px"}}>
                {m[2]}
            </div>
        </div>;
}

impl TelemetryPanel.renderTelemRow(t: dict) -> JsxElement {
    tname = str(t["walker"]);
    ticon = str(t["icon"]);
    tcolor = str(t["color"]);
    tcalls = int(t["calls"]);
    ttokens = int(t["tokens"]);
    tcost = float(str(t["cost"]));
    tlat = int(t["latency"]);
    return
        <div
            key={tname}
            style={{
                "display": "grid",
                "gridTemplateColumns": "190px 1fr 55px 80px 65px",
                "padding": "11px 16px",
                "borderBottom": "0.5px solid rgba(255,255,255,0.04)",
                "alignItems": "center"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "gap": "7px"}}>
                <span>{ticon}</span>
                <span
                    style={{
                        "fontSize": "12px",
                        "fontWeight": "500",
                        "color": (tcolor if tcalls > 0 else "rgba(255,255,255,0.25)")
                    }}
                >
                    {tname}
                </span>
            </div>
            <div>
                <div
                    style={{
                        "height": "3px",
                        "background": "rgba(255,255,255,0.06)",
                        "borderRadius": "2px",
                        "overflow": "hidden"
                    }}
                >
                    <div
                        className="tele-bar-fill"
                        style={{
                            "height": "100%",
                            "width": str(int(tlat / max_lat * 100)) + "%",
                            "background": tcolor,
                            "borderRadius": "2px",
                            "opacity": ("1" if tcalls > 0 else "0.2")
                        }}
                    />
                </div>
                <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)", "marginTop": "3px"}}>
                    {((str(tlat) + "ms") if tlat > 0 else "—")}
                </div>
            </div>
            <div
                style={{
                    "fontSize": "12px",
                    "color": ("rgba(255,255,255,0.8)" if tcalls > 0 else "rgba(255,255,255,0.25)")
                }}
            >
                {(str(tcalls) if tcalls > 0 else "—")}
            </div>
            <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.45)"}}>
                {(str(ttokens) if ttokens > 0 else "—")}
            </div>
            <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.45)"}}>
                {(("$" + str(tcost)) if tcost > 0 else "—")}
            </div>
        </div>;
}

impl TelemetryPanel.renderChainNode(w: dict) -> JsxElement {
    wname = str(w["walker"]);
    wicon = str(w["icon"]);
    wcolor = str(w["color"]);
    wcalls = str(w["calls"]);
    wtime = str(w["time"]);
    return
        <div key={wname} style={{"display": "flex", "alignItems": "center"}}>
            <div style={{"textAlign": "center", "minWidth": "105px"}}>
                <div
                    style={{
                        "width": "38px",
                        "height": "38px",
                        "borderRadius": "50%",
                        "background": wcolor + "15",
                        "border": "1px solid " + wcolor + "45",
                        "display": "flex",
                        "alignItems": "center",
                        "justifyContent": "center",
                        "fontSize": "17px",
                        "margin": "0 auto 5px"
                    }}
                >
                    {wicon}
                </div>
                <div style={{"fontSize": "10px", "fontWeight": "600", "color": wcolor}}>
                    {wname}
                </div>
                <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.3)", "marginTop": "2px"}}>
                    {wcalls} · {wtime}
                </div>
            </div>
            <div
                style={{
                    "width": "24px",
                    "height": "1px",
                    "background": "rgba(255,255,255,0.1)",
                    "flexShrink": "0",
                    "position": "relative"
                }}
            >
                <span
                    style={{
                        "position": "absolute",
                        "right": "-4px",
                        "top": "-8px",
                        "color": "rgba(255,255,255,0.25)",
                        "fontSize": "13px"
                    }}
                >
                    ▸
                </span>
            </div>
        </div>;
}

impl TelemetryPanel.renderEvent(ev: Any, idx: int) -> JsxElement {
    ev_walker = "";
    ev_node = "";
    ev_status = "";
    if ev {
        ev_walker_raw = ev["walker"];
        ev_node_raw = ev["node"];
        ev_status_raw = ev["status"];
        if ev_walker_raw { ev_walker = str(ev_walker_raw); }
        if ev_node_raw { ev_node = str(ev_node_raw); }
        if ev_status_raw { ev_status = str(ev_status_raw); }
    }
    return
        <div
            key={str(idx)}
            style={{
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.45)",
                "padding": "3px 0",
                "display": "flex",
                "alignItems": "center",
                "gap": "6px"
            }}
        >
            <span
                style={{
                    "width": "4px",
                    "height": "4px",
                    "borderRadius": "50%",
                    "background": "#FFE500",
                    "display": "inline-block",
                    "flexShrink": "0"
                }}
            />
            <span style={{"color": "#FFE500"}}>{ev_walker}</span>
            <span>→ {ev_node}</span>
            <span style={{"color": "#00FF88"}}>{ev_status}</span>
        </div>;
}
