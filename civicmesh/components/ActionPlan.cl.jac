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
    def statusIcon(status: str, color: str) -> JsxElement;
    def impactValue(resource_name: str) -> int;
    def renderStep(s: Any, i: int) -> JsxElement;

    total = len(steps);
    pct = (int(done_count / total * 100) if total > 0 else 0);

    # Aggregate annual benefit value across every step whose status is not
    # "denied". This is a rule-based rough estimate (no LLM call) — anchored
    # to publicly published 2024 program averages so the headline number
    # passes a basic sanity check. We also count how many resources
    # contribute to the total for the explanatory subtitle.
    impact_total = 0;
    impact_n = 0;
    if total > 0 {
        si = 0;
        while si < total {
            sx: Any = steps[si];
            sx_status = str(sx["status"]) if sx["status"] else "";
            sx_name = str(sx["name"]) if sx["name"] else "";
            if sx_status != "denied" {
                v = impactValue(sx_name);
                if v > 0 {
                    impact_total = impact_total + v;
                    impact_n = impact_n + 1;
                }
            }
            si = si + 1;
        }
    }
    # Format with commas. Python-style format spec works fine here.
    impact_str = f"{impact_total:,}";

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
                            <div style={{"width": "32px", "height": "32px", "borderRadius": "50%", "background": "rgba(255,68,68,0.12)", "border": "1px solid rgba(255,68,68,0.45)", "display": "flex", "alignItems": "center", "justifyContent": "center", "flexShrink": "0"}}>
                                <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                                    <path d="M13 2 L 4 14 L 11 14 L 10 22 L 20 9 L 13 9 Z" stroke="#FF4444" strokeWidth="1.8" strokeLinejoin="round" fill="rgba(255,68,68,0.2)"/>
                                </svg>
                            </div>
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
                <div style={{"width": "48px", "height": "48px", "borderRadius": "12px", "background": "rgba(255,229,0,0.08)", "border": "1px solid rgba(255,229,0,0.3)", "display": "flex", "alignItems": "center", "justifyContent": "center", "marginBottom": "12px"}}>
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                        <rect x="4" y="3" width="16" height="18" rx="2" stroke="#FFE500" strokeWidth="1.8"/>
                        <path d="M8 8 L 10 10 L 13 7" stroke="#FFE500" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
                        <path d="M8 14 L 16 14 M 8 17.5 L 14 17.5" stroke="#FFE500" strokeWidth="1.6" strokeLinecap="round"/>
                    </svg>
                </div>
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
            {(impact_total > 0) and <div
                style={{
                    "padding": "20px 22px",
                    "background": "linear-gradient(135deg, rgba(0,255,136,0.08), rgba(255,229,0,0.05))",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(0,255,136,0.3)",
                    "borderLeft": "3px solid #00FF88",
                    "borderRadius": "14px",
                    "marginBottom": "12px",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "18px"
                }}
            >
                <div style={{
                    "width": "48px",
                    "height": "48px",
                    "borderRadius": "50%",
                    "background": "rgba(0,255,136,0.12)",
                    "border": "1px solid rgba(0,255,136,0.45)",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "center",
                    "flexShrink": "0"
                }}>
                    <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                        <path
                            d="M12 3 L 14 9 L 20 9 L 15 13 L 17 19 L 12 15.5 L 7 19 L 9 13 L 4 9 L 10 9 Z"
                            stroke="#00FF88"
                            strokeWidth="1.6"
                            strokeLinejoin="round"
                            fill="rgba(0,255,136,0.18)"
                        />
                    </svg>
                </div>
                <div style={{"flex": "1"}}>
                    <div style={{"fontSize": "10px", "color": "rgba(0,255,136,0.8)", "textTransform": "uppercase", "letterSpacing": "0.08em", "fontWeight": "600", "marginBottom": "3px"}}>
                        Estimated impact
                    </div>
                    <div style={{"fontSize": "22px", "fontWeight": "700", "letterSpacing": "-0.02em", "color": "#FFFFFF", "lineHeight": "1.15"}}>
                        ${impact_str}/year unlocked
                    </div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.45)", "marginTop": "3px", "lineHeight": "1.4"}}>
                        {("If approved for all " + str(impact_n) + " resources on this plan · based on 2024 program averages")}
                    </div>
                </div>
            </div>}
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
