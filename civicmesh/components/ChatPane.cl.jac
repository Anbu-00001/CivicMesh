"""CivicMesh chat intake panel.
Left: conversation thread.
Right: detected language + walker chain status sidebar.
"""
sv import from walkers.intake { IntakeWalker }

def:pub ChatPane(
    user_id: str,
    on_walker_event: Any,
    session_data: dict
) -> JsxElement {
    has messages: list[dict] = [],
        input_val: str = "",
        is_loading: bool = False,
        active_walker: str = "",
        detected_language: str = "",
        profile_extracted: Any = {};

    can with entry {
        seed = [
            {
                "role": "bot",
                "text": "Hi! I'm CivicMesh — I help people find housing, food, healthcare, and legal aid. Talk to me in any language. What's going on?",
                "walker": "system"
            }
        ];
        if session_data.get("has_history", False) {
            summary = session_data.get("session_summary", None);
            if summary {
                next_step = summary.get("next_recommended_step", "");
                if next_step {
                    seed = seed + [
                        {
                            "role": "bot",
                            "text": next_step,
                            "walker": "MemoryWalker"
                        }
                    ];
                }
            }
        }
        messages = seed;
    }

    async def sendMessage -> None;
    def renderMessage(msg: dict, idx: int, is_last: bool) -> JsxElement;
    def walkerColor(walker_name: str) -> str;

    profile_category = "";
    profile_urgency = "";
    if profile_extracted {
        try {
            raw_cat = profile_extracted["category"];
            if raw_cat { profile_category = str(raw_cat); }
        } except Exception as _ex { profile_category = ""; }
        try {
            raw_urg = profile_extracted["urgency"];
            if raw_urg { profile_urgency = str(raw_urg); }
        } except Exception as _ex { profile_urgency = ""; }
    }

    walker_chain = [
        ("IntakeWalker", "🚪"),
        ("EligibilityWalker", "🔍"),
        ("NavigationWalker", "🗺"),
        ("MemoryWalker", "🧠"),
        ("EscalationWalker", "⚡")
    ];

    return
        <div
            style={{
                "display": "grid",
                "gridTemplateColumns": "1fr 280px",
                "gap": "14px",
                "height": "calc(100vh - 160px)"
            }}
        >
            <div
                style={{
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "16px",
                    "display": "flex",
                    "flexDirection": "column",
                    "overflow": "hidden"
                }}
            >
                <div
                    style={{
                        "padding": "13px 16px",
                        "borderBottom": "0.5px solid rgba(255,255,255,0.06)",
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "10px"
                    }}
                >
                    <div style={{"flex": "1"}}>
                        <div style={{"fontSize": "14px", "fontWeight": "600"}}>
                            CivicMesh Navigator
                        </div>
                        <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "2px"}}>
                            Multi-agent · 40+ resources · any language
                        </div>
                    </div>
                    {active_walker and <div
                        className="badge-glow"
                        style={{
                            "display": "flex",
                            "alignItems": "center",
                            "gap": "6px",
                            "padding": "4px 10px",
                            "borderRadius": "20px",
                            "background": "rgba(255,229,0,0.1)",
                            "border": "0.5px solid rgba(255,229,0,0.3)"
                        }}
                    >
                        <span
                            className="pulse-ring"
                            style={{"width": "10px", "height": "10px", "flexShrink": "0", "position": "relative"}}
                        >
                            <span
                                style={{
                                    "width": "6px",
                                    "height": "6px",
                                    "borderRadius": "50%",
                                    "background": "#FFE500",
                                    "display": "inline-block",
                                    "position": "relative",
                                    "zIndex": "1"
                                }}
                            />
                        </span>
                        <span style={{"fontSize": "11px", "color": "#FFE500"}}>
                            {active_walker}
                        </span>
                    </div>}
                </div>
                <div
                    style={{
                        "flex": "1",
                        "overflowY": "auto",
                        "padding": "16px",
                        "display": "flex",
                        "flexDirection": "column",
                        "gap": "10px"
                    }}
                >
                    {[renderMessage(messages[i], i, (i == len(messages) - 1) and (not is_loading)) for i in range(len(messages))]}
                    {is_loading and <div style={{"display": "flex", "alignItems": "center", "gap": "8px"}}>
                        <div
                            style={{
                                "width": "28px",
                                "height": "28px",
                                "borderRadius": "50%",
                                "background": "#FFE500",
                                "display": "flex",
                                "alignItems": "center",
                                "justifyContent": "center",
                                "fontSize": "11px",
                                "fontWeight": "700",
                                "color": "#0A0A0A",
                                "flexShrink": "0"
                            }}
                        >
                            CM
                        </div>
                        <div
                            style={{
                                "padding": "10px 14px",
                                "borderRadius": "4px 16px 16px 16px",
                                "background": "rgba(255,255,255,0.06)",
                                "border": "0.5px solid rgba(255,255,255,0.1)",
                                "display": "flex",
                                "gap": "4px",
                                "alignItems": "center"
                            }}
                        >
                            <span style={{"width": "5px", "height": "5px", "borderRadius": "50%", "background": "rgba(255,255,255,0.5)"}}/>
                            <span style={{"width": "5px", "height": "5px", "borderRadius": "50%", "background": "rgba(255,255,255,0.5)"}}/>
                            <span style={{"width": "5px", "height": "5px", "borderRadius": "50%", "background": "rgba(255,255,255,0.5)"}}/>
                        </div>
                    </div>}
                </div>
                <div
                    style={{
                        "padding": "12px 14px",
                        "borderTop": "0.5px solid rgba(255,255,255,0.06)",
                        "display": "flex",
                        "gap": "9px",
                        "alignItems": "center"
                    }}
                >
                    <input
                        value={input_val}
                        onChange={lambda e: ChangeEvent { input_val = e.target.value; }}
                        onKeyDown={lambda e: KeyboardEvent {
                            if e.key == "Enter" { sendMessage(); }
                        }}
                        placeholder="Type in any language..."
                        disabled={is_loading}
                        style={{
                            "flex": "1",
                            "padding": "10px 14px",
                            "background": "#1A1A1A",
                            "border": "0.5px solid rgba(255,255,255,0.1)",
                            "borderRadius": "10px",
                            "color": "#FFFFFF",
                            "fontSize": "14px",
                            "outline": "none"
                        }}
                    />
                    <button
                        onClick={lambda _e: MouseEvent { sendMessage(); }}
                        disabled={is_loading}
                        style={{
                            "width": "38px",
                            "height": "38px",
                            "borderRadius": "50%",
                            "background": ("#FFE500" if (input_val and (not is_loading)) else "rgba(255,255,255,0.06)"),
                            "border": "none",
                            "cursor": "pointer",
                            "fontSize": "16px",
                            "transition": "all 0.2s ease",
                            "flexShrink": "0",
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "center"
                        }}
                    >
                        →
                    </button>
                </div>
            </div>
            <div style={{"display": "flex", "flexDirection": "column", "gap": "12px"}}>
                <div
                    style={{
                        "padding": "14px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.08)",
                        "borderRadius": "14px"
                    }}
                >
                    <div
                        style={{
                            "fontSize": "10px",
                            "color": "rgba(255,255,255,0.35)",
                            "textTransform": "uppercase",
                            "letterSpacing": "0.06em",
                            "marginBottom": "8px"
                        }}
                    >
                        Detected
                    </div>
                    {(<div
                        style={{
                            "fontSize": "26px",
                            "fontWeight": "700",
                            "color": "#FFE500",
                            "letterSpacing": "-0.02em"
                        }}
                    >
                        {detected_language.upper()}
                    </div>) if detected_language else (<div style={{"fontSize": "13px", "color": "rgba(255,255,255,0.2)"}}>Waiting...</div>)}
                    {profile_category and <div
                        style={{
                            "marginTop": "9px",
                            "display": "flex",
                            "flexDirection": "column",
                            "gap": "5px"
                        }}
                    >
                        <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.5)"}}>
                            Need: <span style={{"color": "#FFE500"}}>{profile_category}</span>
                        </div>
                        <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.5)"}}>
                            Urgency: <span style={{"color": "#FFE500"}}>{profile_urgency}</span>
                        </div>
                    </div>}
                </div>
                <div
                    style={{
                        "padding": "14px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.08)",
                        "borderRadius": "14px",
                        "flex": "1"
                    }}
                >
                    <div
                        style={{
                            "fontSize": "10px",
                            "color": "rgba(255,255,255,0.35)",
                            "textTransform": "uppercase",
                            "letterSpacing": "0.06em",
                            "marginBottom": "12px"
                        }}
                    >
                        Walker chain
                    </div>
                    {[
                        <div
                            key={w[0]}
                            style={{
                                "display": "flex",
                                "alignItems": "center",
                                "gap": "8px",
                                "padding": "7px 0",
                                "borderBottom": "0.5px solid rgba(255,255,255,0.04)"
                            }}
                        >
                            <span style={{"fontSize": "14px"}}>{w[1]}</span>
                            <span
                                style={{
                                    "fontSize": "12px",
                                    "color": (walkerColor(w[0]) if (active_walker and (w[0] in active_walker)) else "rgba(255,255,255,0.3)"),
                                    "fontWeight": ("600" if (active_walker and (w[0] in active_walker)) else "400"),
                                    "transition": "all 0.3s ease",
                                    "flex": "1"
                                }}
                            >
                                {w[0]}
                            </span>
                            {(active_walker and (w[0] in active_walker)) and <span
                                className="walker-active-dot"
                                style={{
                                    "width": "6px",
                                    "height": "6px",
                                    "borderRadius": "50%",
                                    "background": walkerColor(w[0]),
                                    "display": "inline-block"
                                }}
                            />}
                        </div>
                        for w in walker_chain
                    ]}
                </div>
            </div>
        </div>;
}
