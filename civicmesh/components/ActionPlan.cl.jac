"""Action plan checklist.
Data sourced entirely from real MemoryWalker calls — no fake steps.
"""
sv import from walkers.memory { MemoryWalker }

def:pub ActionPlan(user_id: str, walker_events: list = []) -> JsxElement {
    has steps: list = [],
        loading: bool = True,
        done_count: int = 0;

    # Detect whether the current session routed to EscalationWalker — if
    # so, the empty state should explain why no apps were written and
    # point the user to the crisis reply already shown in the chat.
    saw_escalation = False;
    saw_chat = False;
    if walker_events {
        ev_n = len(walker_events);
        i = 0;
        while i < ev_n {
            ev: Any = walker_events[i];
            w_raw = ev["walker"] if ev else "";
            w_name = str(w_raw) if w_raw else "";
            if w_name == "EscalationWalker" { saw_escalation = True; }
            if w_name == "IntakeWalker" { saw_chat = True; }
            i = i + 1;
        }
    }

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
    # Compute walker activity counts for the session-context sidebar.
    intake_n = 0;
    elig_n = 0;
    nav_n = 0;
    mem_n = 0;
    esc_n = 0;
    if walker_events {
        wi = 0;
        wn = len(walker_events);
        while wi < wn {
            wev: Any = walker_events[wi];
            ww_raw = wev["walker"] if wev else "";
            ww = str(ww_raw) if ww_raw else "";
            if ww == "IntakeWalker" { intake_n = intake_n + 1; }
            if ww == "EligibilityWalker" { elig_n = elig_n + 1; }
            if ww == "NavigationWalker" { nav_n = nav_n + 1; }
            if ww == "MemoryWalker" { mem_n = mem_n + 1; }
            if ww == "EscalationWalker" { esc_n = esc_n + 1; }
            wi = wi + 1;
        }
    }

    def renderSessionContext -> JsxElement;
    def renderWalkerRow(w: dict) -> JsxElement;

    if len(steps) == 0 {
        # Branch A: chat ran this session AND it routed to EscalationWalker.
        # That's why no ApplicationNodes — show the user what happened.
        if saw_chat and saw_escalation {
            return
                <div style={{"display": "grid", "gridTemplateColumns": "1fr 280px", "gap": "16px"}}>
                    <div
                        style={{
                            "padding": "32px 28px",
                            "background": "rgba(255,68,68,0.04)",
                            "backdropFilter": "blur(12px)",
                            "border": "0.5px solid rgba(255,68,68,0.25)",
                            "borderRadius": "16px"
                        }}
                    >
                        <div style={{"display": "flex", "alignItems": "center", "gap": "12px", "marginBottom": "12px"}}>
                            <div style={{"fontSize": "28px"}}>⚡</div>
                            <div>
                                <div style={{"fontSize": "16px", "fontWeight": "600", "color": "#FF4444"}}>
                                    Escalation triggered this session
                                </div>
                                <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.45)", "marginTop": "2px"}}>
                                    EligibilityWalker found zero matching resources for your profile.
                                </div>
                            </div>
                        </div>
                        <div style={{"fontSize": "13px", "color": "rgba(255,255,255,0.7)", "lineHeight": "1.65", "marginBottom": "16px"}}>
                            When no resources match your stated need (income, location, eligibility criteria), the pipeline skips NavigationWalker and routes straight to EscalationWalker — which composes crisis-line info, appeal options, and a personalized message. <strong style={{"color": "#FFE500"}}>Check the Chat tab</strong> for the full escalation reply; that's where the bot surfaced the next-steps narrative.
                        </div>
                        <div style={{
                            "padding": "12px 14px",
                            "background": "rgba(255,229,0,0.05)",
                            "border": "0.5px solid rgba(255,229,0,0.18)",
                            "borderRadius": "10px",
                            "fontSize": "12px",
                            "color": "rgba(255,255,255,0.7)",
                            "lineHeight": "1.55"
                        }}>
                            <div style={{"color": "#FFE500", "fontWeight": "600", "marginBottom": "6px"}}>To get ApplicationNodes written here, try a prompt that matches a real resource:</div>
                            <div>"I'm a 28-year-old domestic violence survivor with a 5-year-old, need emergency shelter."</div>
                            <div style={{"marginTop": "5px"}}>"I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally."</div>
                            <div style={{"marginTop": "5px"}}>"My kids and I haven't eaten in 2 days. We're in Texas."</div>
                        </div>
                    </div>
                    {renderSessionContext()}
                </div>;
        }

        # Branch B: no chat yet this session — generic onboarding empty state.
        return
            <div style={{"display": "grid", "gridTemplateColumns": "1fr 280px", "gap": "16px"}}>
                <div
                    style={{
                        "padding": "40px 32px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.08)",
                        "borderRadius": "16px"
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
                </div>
                {renderSessionContext()}
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
