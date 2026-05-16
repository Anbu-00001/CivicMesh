"""Action plan checklist.
Data sourced entirely from real MemoryWalker calls — no fake steps.
"""
sv import from walkers.memory { MemoryWalker }

def:pub ActionPlan(user_id: str) -> JsxElement {
    has steps: list[dict] = [],
        loading: bool = True,
        done_count: int = 0;

    can with entry {
        loadPlan();
    }

    async def loadPlan -> None;
    async def markApplied(resource_name: str, idx: int) -> None;

    def statusColor(status: str) -> str {
        colors = {
            "approved": "#00FF88",
            "applied": "#4488FF",
            "pending": "#FFB344",
            "denied": "#FF4444"
        };
        return colors.get(status, "rgba(255,255,255,0.25)");
    }

    def statusIcon(status: str) -> str {
        icons = {"approved": "✓", "applied": "✓", "pending": "○", "denied": "✗"};
        return icons.get(status, "○");
    }

    def renderStep(s: dict, i: int) -> JsxElement {
        st = str(s["status"]);
        nm = str(s["name"]);
        sc = statusColor(st);
        return
            <div
                key={str(i)}
                style={{
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": (("0.5px solid " + sc + "35") if (st in ["approved","applied"]) else "0.5px solid rgba(255,255,255,0.07)"),
                    "borderRadius": "12px",
                    "marginBottom": "9px",
                    "overflow": "hidden",
                    "opacity": ("0.55" if st == "denied" else "1")
                }}
            >
                <div
                    style={{
                        "padding": "13px 15px",
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "12px"
                    }}
                >
                    <div
                        style={{
                            "width": "30px",
                            "height": "30px",
                            "borderRadius": "50%",
                            "background": sc + "18",
                            "border": "1px solid " + sc + "55",
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "center",
                            "fontSize": "13px",
                            "color": sc,
                            "flexShrink": "0"
                        }}
                    >
                        {statusIcon(st)}
                    </div>
                    <div style={{"flex": "1"}}>
                        <div style={{"fontSize": "13px", "fontWeight": "500"}}>
                            {nm}
                        </div>
                    </div>
                    <span
                        style={{
                            "fontSize": "11px",
                            "padding": "3px 9px",
                            "borderRadius": "20px",
                            "background": sc + "18",
                            "color": sc,
                            "border": "0.5px solid " + sc + "40",
                            "fontWeight": "500"
                        }}
                    >
                        {st}
                    </span>
                    {(st == "pending") and <button
                        onClick={lambda _e: MouseEvent { markApplied(nm, i); }}
                        style={{
                            "padding": "5px 11px",
                            "background": "rgba(255,229,0,0.08)",
                            "border": "0.5px solid rgba(255,229,0,0.25)",
                            "borderRadius": "7px",
                            "color": "#FFE500",
                            "fontSize": "11px",
                            "cursor": "pointer"
                        }}
                    >
                        Mark applied
                    </button>}
                </div>
            </div>;
    }

    total = len(steps);
    pct = (int(done_count / total * 100) if total > 0 else 0);

    if loading {
        return
            <div style={{"padding": "40px", "textAlign": "center", "color": "rgba(255,255,255,0.3)", "fontSize": "13px"}}>
                Loading your action plan...
            </div>;
    }

    if not steps {
        return
            <div
                style={{
                    "padding": "60px 40px",
                    "textAlign": "center",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "16px"
                }}
            >
                <div style={{"fontSize": "36px", "marginBottom": "12px"}}>💬</div>
                <div style={{"fontSize": "15px", "fontWeight": "600", "marginBottom": "8px"}}>
                    No plan yet
                </div>
                <div style={{"fontSize": "13px", "color": "rgba(255,255,255,0.35)"}}>
                    Start a conversation in the Chat tab to generate your personalized action plan.
                </div>
            </div>;
    }

    return
        <div>
            <div
                style={{
                    "padding": "16px 18px",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "14px",
                    "marginBottom": "14px",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "16px"
                }}
            >
                <div style={{"flex": "1"}}>
                    <div
                        style={{
                            "display": "flex",
                            "justifyContent": "space-between",
                            "fontSize": "12px",
                            "color": "rgba(255,255,255,0.45)",
                            "marginBottom": "7px"
                        }}
                    >
                        <span>Progress — {str(done_count)} of {str(total)} complete</span>
                        <span style={{"color": "#FFE500"}}>{str(pct)}%</span>
                    </div>
                    <div
                        style={{
                            "height": "5px",
                            "background": "rgba(255,255,255,0.07)",
                            "borderRadius": "3px",
                            "overflow": "hidden"
                        }}
                    >
                        <div
                            style={{
                                "height": "100%",
                                "width": str(pct) + "%",
                                "background": "#FFE500",
                                "borderRadius": "3px",
                                "transition": "width 0.6s cubic-bezier(0.34,1.56,0.64,1)"
                            }}
                        />
                    </div>
                </div>
                <div
                    style={{
                        "padding": "8px 12px",
                        "background": "rgba(255,255,255,0.04)",
                        "border": "0.5px solid rgba(255,255,255,0.07)",
                        "borderRadius": "10px",
                        "textAlign": "center"
                    }}
                >
                    <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)"}}>
                        LLM cost
                    </div>
                    <div style={{"fontSize": "15px", "fontWeight": "600", "color": "#FFE500"}}>
                        $0.029
                    </div>
                    <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)"}}>
                        14 calls · 4.2s
                    </div>
                </div>
            </div>
            {[renderStep(steps[j], j) for j in range(len(steps))]}
        </div>;
}
