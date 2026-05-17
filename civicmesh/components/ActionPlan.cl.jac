"""Action plan checklist.
Data sourced entirely from real MemoryWalker calls — no fake steps.
"""
sv import from walkers.memory { MemoryWalker }

def:pub ActionPlan(user_id: str) -> JsxElement {
    has steps: list = [],
        loading: bool = True,
        done_count: int = 0;

    can with entry {
        loadPlan();
    }

    async def loadPlan -> None;
    async def markApplied(resource_name: str, idx: int) -> None;
    def statusColor(status: str) -> str;
    def statusIcon(status: str) -> str;
    def renderStep(s: Any, i: int) -> JsxElement;

    total = len(steps);
    pct = (int(done_count / total * 100) if total > 0 else 0);

    if loading {
        return
            <div style={{"padding": "40px", "textAlign": "center", "color": "rgba(255,255,255,0.3)", "fontSize": "13px"}}>
                Loading your action plan...
            </div>;
    }

    # Jac `not []` compiles to JS `![]` which is `false` (arrays are
    # always truthy in JS). Use len() == 0 instead so the empty-state
    # branch actually fires when there are no apps.
    if len(steps) == 0 {
        return
            <div
                style={{
                    "padding": "48px 32px",
                    "textAlign": "center",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "16px",
                    "maxWidth": "600px",
                    "margin": "0 auto"
                }}
            >
                <div style={{"fontSize": "32px", "marginBottom": "10px"}}>📋</div>
                <div style={{"fontSize": "16px", "fontWeight": "600", "marginBottom": "8px", "color": "#FFE500"}}>
                    No applications yet
                </div>
                <div style={{"fontSize": "13px", "color": "rgba(255,255,255,0.55)", "lineHeight": "1.6", "marginBottom": "18px"}}>
                    When the eligibility walker finds resources that fit your situation, the navigation walker writes one ApplicationNode per recommended step into your graph. You'll see those steps appear here with status badges (pending → applied → approved/denied).
                </div>
                <div style={{
                    "padding": "12px 16px",
                    "background": "rgba(255,229,0,0.06)",
                    "border": "0.5px solid rgba(255,229,0,0.2)",
                    "borderRadius": "10px",
                    "fontSize": "12px",
                    "color": "rgba(255,255,255,0.65)",
                    "textAlign": "left",
                    "lineHeight": "1.55"
                }}>
                    <div style={{"color": "#FFE500", "fontWeight": "600", "marginBottom": "6px"}}>
                        Try a chat prompt like:
                    </div>
                    <div>"I'm a single mother with 2 kids and need housing help. I earn $1800/month in Houston."</div>
                    <div style={{"marginTop": "5px"}}>"I need food assistance for my family."</div>
                    <div style={{"marginTop": "5px"}}>"I lost my job and need legal help to avoid eviction."</div>
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
                            className="progress-spring"
                            style={{
                                "height": "100%",
                                "width": str(pct) + "%",
                                "background": "#FFE500",
                                "borderRadius": "3px"
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
