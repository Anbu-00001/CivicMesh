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

    def renderMetric(m: tuple) -> JsxElement;
    def renderTelemRow(t: dict) -> JsxElement;
    def renderChainNode(w: dict) -> JsxElement;
    def renderEvent(ev: Any, idx: int) -> JsxElement;

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
                    {[renderEvent(walker_events[j], j) for j in range(max(0, len(walker_events)-5), len(walker_events))]}
                </div>}
            </div>
        </div>;
}
