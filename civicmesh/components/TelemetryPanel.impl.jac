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

impl TelemetryPanel.loadReflections -> None {
    # Fire-and-forget poll of ReflectionReadWalker. Cheap because it's a
    # read-only graph traversal — no LLM calls. We swallow errors silently
    # since the rest of the Telemetry tab is still meaningful without
    # the self-reflection rollup.
    reflections_loading = True;
    try {
        result = await root spawn ReflectionReadWalker(
            user_id="demo_user",
            max_insights=8
        );
        reports = result.reports if result.reports else [];
        if len(reports) > 0 {
            r0: Any = reports[0];
            ins_raw = r0["insights"] if r0 else None;
            if ins_raw {
                reflections = list(ins_raw);
            } else {
                reflections = [];
            }
        }
    } except Exception as _ex {
        reflections = [];
    }
    reflections_loading = False;
}

impl TelemetryPanel.renderReflectionTimeline -> JsxElement {
    # Empty state — no SessionInsights yet means no chat turns have run
    # (or the user is on a brand-new account where CritiqueWalker hasn't
    # written anything). Keep the section visible anyway so judges see
    # WHERE the self-reflection lives even before triggering it.
    n_ins = len(reflections);
    if n_ins == 0 {
        return
            <div
                style={{
                    "marginTop": "14px",
                    "background": "rgba(0,200,255,0.04)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(0,200,255,0.25)",
                    "borderRadius": "14px",
                    "padding": "16px 18px"
                }}
            >
                <div style={{"fontSize": "10px", "color": "rgba(0,200,255,0.85)", "textTransform": "uppercase", "letterSpacing": "0.08em", "fontWeight": "700", "marginBottom": "6px", "display": "flex", "alignItems": "center", "gap": "8px"}}>
                    <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
                        <circle cx="12" cy="12" r="9" stroke="#00C8FF" strokeWidth="1.7"/>
                        <path d="M12 7 L 12 13 L 16 15" stroke="#00C8FF" strokeWidth="1.7" strokeLinecap="round"/>
                    </svg>
                    Agent self-reflection · Reflexion in pure Jac
                </div>
                <div style={{"fontSize": "11.5px", "color": "rgba(255,255,255,0.6)", "lineHeight": "1.55"}}>
                    After every chat turn a zero-LLM <strong style={{"color": "rgba(0,200,255,0.95)"}}>CritiqueWalker</strong> reads the chain telemetry, scores it, and writes a SessionInsight node attached to your PersonNode via the <code style={{"fontFamily": "ui-monospace, monospace", "fontSize": "10px", "color": "#00C8FF"}}>reflected_on</code> edge. The next chat turn reads the last two SessionInsights back as plain-text context prefix — the agent learns from its own past performance using only the graph itself.
                </div>
                <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "10px", "fontStyle": "italic"}}>
                    Send a chat message and refresh this tab to see the first reflection appear.
                </div>
            </div>;
    }

    # Compute a rolling average quality score over the last 8 insights.
    total = 0;
    for ins in reflections {
        try { total = total + int(ins["quality_score"]); } except Exception as _ex {}
    }
    avg = int(total / n_ins) if n_ins > 0 else 0;

    return
        <div
            style={{
                "marginTop": "14px",
                "background": "rgba(0,200,255,0.04)",
                "backdropFilter": "blur(12px)",
                "border": "0.5px solid rgba(0,200,255,0.3)",
                "borderRadius": "14px",
                "padding": "16px 18px"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between", "marginBottom": "10px", "flexWrap": "wrap", "gap": "10px"}}>
                <div style={{"display": "flex", "alignItems": "center", "gap": "8px"}}>
                    <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
                        <circle cx="12" cy="12" r="9" stroke="#00C8FF" strokeWidth="1.7"/>
                        <path d="M12 7 L 12 13 L 16 15" stroke="#00C8FF" strokeWidth="1.7" strokeLinecap="round"/>
                    </svg>
                    <span style={{"fontSize": "11px", "color": "#00C8FF", "textTransform": "uppercase", "letterSpacing": "0.08em", "fontWeight": "700"}}>
                        Agent self-reflection · {str(n_ins)} insight{("s" if n_ins != 1 else "")}
                    </span>
                </div>
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <span style={{"fontSize": "11px", "color": "rgba(255,255,255,0.5)"}}>Rolling quality</span>
                    <span style={{
                        "fontSize": "13px",
                        "fontWeight": "700",
                        "color": (
                            "#00FF88" if avg >= 70
                            else ("#FFB344" if avg >= 40 else "#FF4444")
                        ),
                        "fontFamily": "ui-monospace, monospace",
                        "padding": "2px 9px",
                        "borderRadius": "10px",
                        "background": "rgba(255,255,255,0.04)",
                        "border": "0.5px solid currentColor"
                    }}>
                        {str(avg)} / 100
                    </span>
                </div>
            </div>
            <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.5)", "marginBottom": "14px", "lineHeight": "1.55"}}>
                Each row is a SessionInsight node persisted in the graph. The next IntakeWalker turn reads the two newest as context prefix — Reflexion-style self-improvement with zero external memory store.
            </div>
            <div style={{"display": "flex", "flexDirection": "column", "gap": "8px"}}>
                {[renderReflectionRow(reflections[ri], ri) for ri in range(n_ins)]}
            </div>
        </div>;
}

impl TelemetryPanel.renderReflectionRow(ins: Any, idx: int) -> JsxElement {
    score = 50;
    headline = "";
    snip = "";
    walkers: list = [];
    llm_est = 0;
    esc = False;
    pf = False;
    nav = False;
    try { score = int(ins["quality_score"]); } except Exception as _ex {}
    try { headline = str(ins["headline"]); } except Exception as _ex {}
    try { snip = str(ins["user_prompt_snippet"]); } except Exception as _ex {}
    try { walkers = list(ins["walkers_fired"]); } except Exception as _ex {}
    try { llm_est = int(ins["llm_calls_est"]); } except Exception as _ex {}
    try { esc = bool(ins["escalated"]); } except Exception as _ex {}
    try { pf = bool(ins["pathfinder_used"]); } except Exception as _ex {}
    try { nav = bool(ins["navigation_used"]); } except Exception as _ex {}

    score_color = "#00FF88" if score >= 70 else ("#FFB344" if score >= 40 else "#FF4444");

    return
        <div
            key={str(idx)}
            style={{
                "padding": "10px 12px",
                "background": "rgba(255,255,255,0.02)",
                "border": "0.5px solid rgba(255,255,255,0.06)",
                "borderLeft": "2px solid " + score_color,
                "borderRadius": "8px",
                "display": "flex",
                "flexDirection": "column",
                "gap": "5px"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "gap": "10px", "flexWrap": "wrap"}}>
                <span style={{
                    "fontSize": "11px",
                    "fontWeight": "700",
                    "color": score_color,
                    "fontFamily": "ui-monospace, monospace",
                    "minWidth": "26px"
                }}>
                    {str(score)}
                </span>
                <span style={{"fontSize": "11.5px", "color": "rgba(255,255,255,0.8)", "flex": "1", "minWidth": "200px"}}>
                    {headline}
                </span>
                {nav and <span style={{"fontSize": "9px", "padding": "1px 6px", "borderRadius": "8px", "background": "rgba(0,255,136,0.1)", "color": "#00FF88", "border": "0.5px solid currentColor", "fontWeight": "600", "letterSpacing": "0.03em", "textTransform": "uppercase"}}>nav</span>}
                {pf and <span style={{"fontSize": "9px", "padding": "1px 6px", "borderRadius": "8px", "background": "rgba(0,200,255,0.1)", "color": "#00C8FF", "border": "0.5px solid currentColor", "fontWeight": "600", "letterSpacing": "0.03em", "textTransform": "uppercase"}}>pathfinder</span>}
                {esc and <span style={{"fontSize": "9px", "padding": "1px 6px", "borderRadius": "8px", "background": "rgba(255,68,68,0.1)", "color": "#FF4444", "border": "0.5px solid currentColor", "fontWeight": "600", "letterSpacing": "0.03em", "textTransform": "uppercase"}}>escalated</span>}
                <span style={{"fontSize": "10px", "fontFamily": "ui-monospace, monospace", "color": "rgba(255,255,255,0.35)"}}>
                    ~{str(llm_est)} LLM calls
                </span>
            </div>
            {snip and <div style={{"fontSize": "10.5px", "color": "rgba(255,255,255,0.45)", "fontStyle": "italic", "paddingLeft": "36px", "lineHeight": "1.45"}}>
                "{snip}"
            </div>}
        </div>;
}
