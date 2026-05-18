"""Render helpers for TelemetryPanel — all data is derived from walker_events."""

impl TelemetryPanel.renderWalkerRow(name: str) -> JsxElement {
    meta: Any = walker_meta[name];
    icon = str(meta["icon"]) if meta else "";
    color = str(meta["color"]) if meta else "#666";
    count = int(counts[name]) if name in counts else 0;
    is_active = bool(triggered[name]) if name in triggered else False;
    pct = (int(count / total_events * 100) if total_events > 0 else 0);
    return
        <div
            key={name}
            style={{
                "display": "grid",
                "gridTemplateColumns": "190px 1fr 80px",
                "padding": "11px 16px",
                "borderBottom": "0.5px solid rgba(255,255,255,0.04)",
                "alignItems": "center"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "gap": "7px"}}>
                <span>{icon}</span>
                <span
                    style={{
                        "fontSize": "12px",
                        "fontWeight": "500",
                        "color": (color if is_active else "rgba(255,255,255,0.25)")
                    }}
                >
                    {name}
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
                            "width": (str(pct) + "%"),
                            "background": color,
                            "borderRadius": "2px",
                            "opacity": ("1" if is_active else "0.2")
                        }}
                    />
                </div>
                <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)", "marginTop": "3px"}}>
                    {(str(pct) + "% of session activity" if is_active else "not triggered this session")}
                </div>
            </div>
            <div
                style={{
                    "fontSize": "13px",
                    "fontWeight": "600",
                    "textAlign": "right",
                    "color": (color if is_active else "rgba(255,255,255,0.25)")
                }}
            >
                {(str(count) + (" event" if count == 1 else " events"))}
            </div>
        </div>;
}

impl TelemetryPanel.renderChainNode(name: str, is_triggered: bool, count: int) -> JsxElement {
    meta: Any = walker_meta[name];
    icon = str(meta["icon"]) if meta else "";
    color = str(meta["color"]) if meta else "#666";
    is_last = name == "EscalationWalker";
    return
        <div key={name} style={{"display": "flex", "alignItems": "center"}}>
            <div style={{"textAlign": "center", "minWidth": "105px", "opacity": ("1" if is_triggered else "0.35")}}>
                <div
                    style={{
                        "width": "38px",
                        "height": "38px",
                        "borderRadius": "50%",
                        "background": color + "15",
                        "border": "1px solid " + color + ("88" if is_triggered else "30"),
                        "display": "flex",
                        "alignItems": "center",
                        "justifyContent": "center",
                        "fontSize": "17px",
                        "margin": "0 auto 5px"
                    }}
                >
                    {icon}
                </div>
                <div style={{"fontSize": "10px", "fontWeight": "600", "color": color}}>
                    {name}
                </div>
                <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)", "marginTop": "2px"}}>
                    {((str(count) + (" event" if count == 1 else " events")) if is_triggered else "not triggered")}
                </div>
            </div>
            {(not is_last) and <div
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
            </div>}
        </div>;
}

impl TelemetryPanel.renderCallCard(name: str) -> JsxElement {
    meta: Any = walker_meta[name];
    color = str(meta["color"]) if meta else "#666";
    call: Any = walker_calls[name];
    in_str = str(call["input"]) if call else "";
    out_str = str(call["output"]) if call else "";
    stub_str = str(call["stub"]) if call else "";
    uses_tools = bool(call["tools"]) if call else False;
    count = int(counts[name]) if name in counts else 0;
    return
        <div
            key={"call-" + name}
            style={{
                "padding": "12px 14px",
                "background": "rgba(255,255,255,0.02)",
                "border": "0.5px solid " + color + "30",
                "borderLeft": "2px solid " + color,
                "borderRadius": "10px",
                "display": "flex",
                "flexDirection": "column",
                "gap": "6px"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "gap": "8px", "flexWrap": "wrap"}}>
                <span style={{
                    "fontSize": "12px",
                    "fontWeight": "600",
                    "color": color,
                    "letterSpacing": "-0.01em"
                }}>
                    {name}
                </span>
                <span style={{
                    "fontSize": "9px",
                    "padding": "1px 6px",
                    "borderRadius": "8px",
                    "background": color + "15",
                    "color": color,
                    "border": "0.5px solid " + color + "40",
                    "letterSpacing": "0.02em",
                    "fontFamily": "ui-monospace, monospace"
                }}>
                    {stub_str}
                </span>
                <span style={{"flex": "1"}}/>
                <span style={{
                    "fontSize": "10px",
                    "padding": "1px 7px",
                    "borderRadius": "8px",
                    "background": ("rgba(0,255,136,0.08)" if uses_tools else "rgba(255,255,255,0.04)"),
                    "color": ("#00FF88" if uses_tools else "rgba(255,255,255,0.4)"),
                    "border": ("0.5px solid rgba(0,255,136,0.3)" if uses_tools else "0.5px solid rgba(255,255,255,0.08)")
                }}>
                    {("tools: yes" if uses_tools else "tools: no")}
                </span>
                <span style={{
                    "fontSize": "10px",
                    "color": "rgba(255,255,255,0.4)",
                    "fontFamily": "ui-monospace, monospace"
                }}>
                    {str(count) + (" event" if count == 1 else " events")}
                </span>
            </div>
            <div style={{
                "display": "grid",
                "gridTemplateColumns": "70px 1fr",
                "gap": "4px 10px",
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.55)",
                "lineHeight": "1.45",
                "marginTop": "2px"
            }}>
                <div style={{"color": "rgba(255,255,255,0.35)", "textTransform": "uppercase", "fontSize": "9px", "letterSpacing": "0.06em", "paddingTop": "2px"}}>Input</div>
                <div style={{"fontFamily": "ui-monospace, monospace", "color": "rgba(255,255,255,0.7)"}}>{in_str}</div>
                <div style={{"color": "rgba(255,255,255,0.35)", "textTransform": "uppercase", "fontSize": "9px", "letterSpacing": "0.06em", "paddingTop": "2px"}}>Output</div>
                <div style={{"fontFamily": "ui-monospace, monospace", "color": color}}>{out_str}</div>
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
    status_color = "#00FF88" if ev_status == "complete" else "#FFB344";
    return
        <div
            key={str(idx)}
            style={{
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.55)",
                "padding": "4px 0",
                "display": "flex",
                "alignItems": "center",
                "gap": "8px"
            }}
        >
            <span style={{"fontSize": "10px", "color": "rgba(255,255,255,0.3)", "minWidth": "20px"}}>
                {"#" + str(idx + 1)}
            </span>
            <span style={{"color": "#FFE500", "minWidth": "150px"}}>{ev_walker}</span>
            <span style={{"color": "rgba(255,255,255,0.35)"}}>→</span>
            <span style={{"minWidth": "140px"}}>{ev_node}</span>
            <span style={{"color": status_color, "fontWeight": "500"}}>{ev_status}</span>
        </div>;
}
