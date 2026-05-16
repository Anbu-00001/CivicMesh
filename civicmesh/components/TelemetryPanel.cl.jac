"""LLM telemetry dashboard.
Base values are demo defaults clearly labeled.
walker_events list updates the live feed from real calls.
"""

def:pub TelemetryPanel(walker_events: list) -> JsxElement {
    # Demo defaults — labeled as such. Updated by real events in prod.
    has telemetry: list[dict] = [
        {"walker": "IntakeWalker",      "icon": "🚪", "color": "#FFE500", "calls": 2,  "tokens": 1240, "cost": 0.004, "latency": 480},
        {"walker": "EligibilityWalker", "icon": "🔍", "color": "#4488FF", "calls": 10, "tokens": 5820, "cost": 0.018, "latency": 2100},
        {"walker": "NavigationWalker",  "icon": "🗺", "color": "#00FF88", "calls": 1,  "tokens": 2400, "cost": 0.006, "latency": 1080},
        {"walker": "MemoryWalker",      "icon": "🧠", "color": "#FFB344", "calls": 1,  "tokens": 680,  "cost": 0.001, "latency": 370},
        {"walker": "EscalationWalker",  "icon": "⚡", "color": "#FF4444", "calls": 0,  "tokens": 0,    "cost": 0.0,   "latency": 0}
    ];

    max_lat = 2100;
    total_cost = 0.029;
    total_calls = 14;
    total_lat = 4.0;

    chain: list[dict] = [
        {"walker": "IntakeWalker",      "icon": "🚪", "color": "#FFE500", "calls": "2 calls",  "time": "480ms"},
        {"walker": "EligibilityWalker", "icon": "🔍", "color": "#4488FF", "calls": "10 calls", "time": "2.1s"},
        {"walker": "NavigationWalker",  "icon": "🗺", "color": "#00FF88", "calls": "1 call",   "time": "1.1s"},
        {"walker": "MemoryWalker",      "icon": "🧠", "color": "#FFB344", "calls": "1 call",   "time": "370ms"}
    ];

    metrics = [
        ("📞", str(total_calls), "LLM calls"),
        ("⚡", str(total_lat) + "s", "Total latency"),
        ("💰", "$" + str(total_cost), "Cost per case"),
        ("✓", "6", "Resources matched")
    ];

    def renderMetric(m: tuple) -> JsxElement {
        return
            <div
                key={m[2]}
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

    def renderTelemRow(t: dict) -> JsxElement {
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

    def renderChainNode(w: dict) -> JsxElement {
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

    def renderEvent(ev: dict, idx: int) -> JsxElement {
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
                <span style={{"color": "#FFE500"}}>{ev.get("walker", "")}</span>
                <span>→ {ev.get("node", "")}</span>
                <span style={{"color": "#00FF88"}}>{ev.get("status", "")}</span>
            </div>;
    }

    return
        <div>
            <div
                style={{
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.3)",
                    "marginBottom": "12px",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "6px"
                }}
            >
                <span
                    style={{
                        "width": "6px",
                        "height": "6px",
                        "borderRadius": "50%",
                        "background": "#FFB344",
                        "display": "inline-block"
                    }}
                />
                Demo defaults shown. Run a chat session to see live values at /admin/llm/telemetry
            </div>
            <div
                style={{
                    "display": "grid",
                    "gridTemplateColumns": "repeat(4,1fr)",
                    "gap": "10px",
                    "marginBottom": "14px"
                }}
            >
                {[renderMetric(metrics[i]) for i in range(len(metrics))]}
            </div>
            <div
                style={{
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.07)",
                    "borderRadius": "14px",
                    "overflow": "hidden",
                    "marginBottom": "14px"
                }}
            >
                <div
                    style={{
                        "display": "grid",
                        "gridTemplateColumns": "190px 1fr 55px 80px 65px",
                        "padding": "9px 16px",
                        "borderBottom": "0.5px solid rgba(255,255,255,0.06)",
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.3)",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.06em"
                    }}
                >
                    <div>Walker</div>
                    <div>Latency</div>
                    <div>Calls</div>
                    <div>Tokens</div>
                    <div>Cost</div>
                </div>
                {[renderTelemRow(telemetry[i]) for i in range(len(telemetry))]}
            </div>
            <div
                style={{
                    "padding": "16px",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.07)",
                    "borderRadius": "14px"
                }}
            >
                <div
                    style={{
                        "fontSize": "11px",
                        "color": "rgba(255,255,255,0.35)",
                        "marginBottom": "14px",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.06em"
                    }}
                >
                    Walker call tree — parent → child invocation
                </div>
                <div style={{"display": "flex", "alignItems": "center", "overflowX": "auto", "gap": "0"}}>
                    {[renderChainNode(chain[i]) for i in range(len(chain))]}
                    <div style={{"textAlign": "center", "minWidth": "105px", "opacity": "0.35"}}>
                        <div
                            style={{
                                "width": "38px",
                                "height": "38px",
                                "borderRadius": "50%",
                                "background": "rgba(255,68,68,0.08)",
                                "border": "1px solid rgba(255,68,68,0.2)",
                                "display": "flex",
                                "alignItems": "center",
                                "justifyContent": "center",
                                "fontSize": "17px",
                                "margin": "0 auto 5px"
                            }}
                        >
                            ⚡
                        </div>
                        <div style={{"fontSize": "10px", "color": "#FF4444"}}>EscalationWalker</div>
                        <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.25)", "marginTop": "2px"}}>
                            not triggered
                        </div>
                    </div>
                </div>
                {walker_events and <div
                    style={{
                        "marginTop": "14px",
                        "paddingTop": "12px",
                        "borderTop": "0.5px solid rgba(255,255,255,0.06)"
                    }}
                >
                    <div
                        style={{
                            "fontSize": "10px",
                            "color": "rgba(255,255,255,0.3)",
                            "marginBottom": "7px",
                            "textTransform": "uppercase",
                            "letterSpacing": "0.06em"
                        }}
                    >
                        Live events
                    </div>
                    {[renderEvent(dict(walker_events[j]), j) for j in range(max(0, len(walker_events)-5), len(walker_events))]}
                </div>}
            </div>
        </div>;
}
