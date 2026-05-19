"""CivicMesh chat intake panel.
Left: conversation thread.
Right: detected language + walker chain status sidebar.
"""
sv import from walkers.intake { IntakeWalker }
sv import from walkers.translate { TranslateWalker }

def:pub ChatPane(
    user_id: str,
    on_walker_event: Any,
    session_data: dict,
    walker_events: list = []
) -> JsxElement {
    has messages: list[dict] = [],
        input_val: str = "",
        is_loading: bool = False,
        active_walker: str = "",
        detected_language: str = "",
        profile_extracted: Any = {},
        open_trace_idx: int = -1,
        translation_cache: dict = {},
        # Voice-intake state. The Web Speech API is browser-native, free,
        # and runs entirely client-side — no upload to AssemblyAI / OpenAI
        # Realtime, no per-minute charge, no new LLM tokens consumed. A
        # user in crisis who can't type effectively (limited literacy,
        # disability, panic) can press a mic button and dictate in any
        # supported language. The transcribed text flows through the same
        # IntakeWalker as keyboard input — one walker chain handles every
        # input modality.
        voice_listening: bool = False,
        voice_supported: bool = True,
        voice_interim: str = "";

    can with entry {
        # Cold-start welcome with three click-to-send sample prompts.
        # On a hackathon demo the judge launches the app, reads the welcome,
        # then has no idea what to type — the prompt chips remove that
        # friction. They cover the three top categories (housing/food/legal)
        # and explicitly mention income + family size so EligibilityWalker
        # has enough to score against in one turn.
        seed = [
            {
                "role": "bot",
                "text": "Hi! I'm CivicMesh — I help people find housing, food, healthcare, and legal aid. Talk to me in any language. Pick a prompt below or describe your situation in your own words.",
                "walker": "system",
                "suggestions": [
                    "I'm a single mother with 2 kids in Houston. I earn $1,800/month and need housing help.",
                    "Mi familia y yo no hemos comido en 2 días. Estamos en Texas.",
                    "I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally."
                ]
            }
        ];
        # session_data comes back from MemoryWalker as a plain JSON object,
        # not a real Jac dict — `.get()` is undefined on plain objects in
        # JS, so calling it crashes the render with "summary.get is not a
        # function". Use bracket access in try/except instead so a missing
        # field returns None without exploding.
        has_history_flag = False;
        try {
            has_history_flag = bool(session_data["has_history"]);
        } except Exception as _ex {}
        if has_history_flag {
            summary: Any = None;
            try {
                summary = session_data["session_summary"];
            } except Exception as _ex {}
            if summary {
                next_step = "";
                try {
                    nrs = summary["next_recommended_step"];
                    if nrs { next_step = str(nrs); }
                } except Exception as _ex {}
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

    async def sendMessage(text_override: str = "") -> None;
    def renderMessage(msg: dict, idx: int, is_last: bool) -> JsxElement;
    def renderTraceStep(step: Any, idx: int) -> JsxElement;
    def renderSuggestionChip(text: str) -> JsxElement;
    def renderEscapePath(path: Any, idx: int) -> JsxElement;
    def walkerColor(walker_name: str) -> str;
    def isLowSignal(text: str) -> bool;
    def generateSuggestions(profile: Any, escalated: bool, bot_walker: str, user_text: str) -> list;
    def detectIntent(text: str) -> str;

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

    # Each walker: name, color accent, one-line role, live status text
    walker_pipeline: list[dict] = [
        {"name": "IntakeWalker",      "color": "#FFE500", "role": "Extracts your need + language", "live": "Parsing your message..."},
        {"name": "EligibilityWalker", "color": "#4488FF", "role": "Scores 40 resources against your profile", "live": "Scoring eligibility..."},
        {"name": "NavigationWalker",  "color": "#00FF88", "role": "Builds the ordered action plan",     "live": "Building action plan..."},
        {"name": "MemoryWalker",      "color": "#FFB344", "role": "Persists your session for return visits", "live": "Saving session state..."},
        {"name": "EscalationWalker",  "color": "#FF4444", "role": "Routes to crisis lines if no match",     "live": "Composing escalation..."}
    ];

    # Map walker name -> what state this walker is in for the current turn:
    #   "complete" (already seen a "complete" event)
    #   "active"   (has a "running" event but no "complete")
    #   "idle"     (not seen yet this session)
    def walkerState(name: str) -> str;
    def renderWalkerNode(w: dict, is_last: bool) -> JsxElement;

    return
        <div
            style={{
                "display": "grid",
                "gridTemplateColumns": "1fr 240px",
                "gap": "12px",
                "height": "calc(100vh - 96px)"
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
                        Walker pipeline
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "0"}}>
                        {[renderWalkerNode(walker_pipeline[i], i == len(walker_pipeline) - 1) for i in range(len(walker_pipeline))]}
                    </div>
                </div>
            </div>
        </div>;
}
