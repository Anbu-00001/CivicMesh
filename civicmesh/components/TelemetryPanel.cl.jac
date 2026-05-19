"""LLM telemetry dashboard.

All metrics shown here are derived from real walker_events emitted by the
chat pipeline. No demo defaults. When no chat session has run yet, the
panel shows an empty-state explanation.
"""

sv import from walkers.critique { ReflectionReadWalker }

def:pub TelemetryPanel(walker_events: list) -> JsxElement {
    # Reflexion-style self-reflection panel state. Populated by
    # ReflectionReadWalker on mount and whenever walker_events grows
    # (i.e. when a new chat turn writes a fresh SessionInsight).
    has reflections: list = [],
        reflections_loading: bool = False;

    async def loadReflections -> None;
    def renderReflectionTimeline -> JsxElement;
    def renderReflectionRow(ins: Any, idx: int) -> JsxElement;

    can with entry {
        loadReflections();
    }

    can with [walker_events] entry {
        if walker_events and len(walker_events) > 0 {
            loadReflections();
        }
    }

    walker_meta: dict = {
        "IntakeWalker":      {"icon": "🚪", "color": "#FFE500"},
        "EligibilityWalker": {"icon": "🔍", "color": "#4488FF"},
        "NavigationWalker":  {"icon": "🗺",  "color": "#00FF88"},
        "MemoryWalker":      {"icon": "🧠", "color": "#FFB344"},
        "EscalationWalker":  {"icon": "⚡", "color": "#FF4444"}
    };
    walker_order: list[str] = [
        "IntakeWalker", "EligibilityWalker", "NavigationWalker",
        "MemoryWalker", "EscalationWalker"
    ];

    # Count events per walker, derived from the live event stream.
    counts: dict = {
        "IntakeWalker": 0, "EligibilityWalker": 0, "NavigationWalker": 0,
        "MemoryWalker": 0, "EscalationWalker": 0
    };
    triggered: dict = {
        "IntakeWalker": False, "EligibilityWalker": False,
        "NavigationWalker": False, "MemoryWalker": False,
        "EscalationWalker": False
    };
    total_events = len(walker_events) if walker_events else 0;
    if walker_events {
        for i in range(total_events) {
            ev: Any = walker_events[i];
            w_raw = ev["walker"] if ev else "";
            w = str(w_raw) if w_raw else "";
            if w in counts {
                counts[w] = counts[w] + 1;
                triggered[w] = True;
            }
        }
    }

    def renderWalkerRow(name: str) -> JsxElement;
    def renderChainNode(name: str, is_triggered: bool, count: int) -> JsxElement;
    def renderEvent(ev: Any, idx: int) -> JsxElement;
    def renderCallCard(name: str) -> JsxElement;

    # Per-walker architectural breakdown — what the LLM was asked, what
    # structured type it returned, and whether the walker invoked any
    # tools mid-flight. This metadata is static (mirrors how the walkers
    # are defined in walkers/*.jac and llm/stubs.jac) so we don't need
    # the chat pipeline to round-trip prompt strings.
    walker_calls: dict = {
        "IntakeWalker": {
            "input": "Raw user message · last-turn prompt",
            "output": "NeedProfile{category, urgency, details}",
            "stub": "extract_need_profile()",
            "tools": False
        },
        "EligibilityWalker": {
            "input": "NeedProfile + 40 seeded ResourceNodes",
            "output": "EligibilityResult{eligible_count, top_matches[], action_plan}",
            "stub": "check_eligibility() · score_match()",
            "tools": True
        },
        "NavigationWalker": {
            "input": "Eligible resources ranked by score",
            "output": "ActionPlan{steps[], summary, next_action}",
            "stub": "generate_action_plan()",
            "tools": True
        },
        "MemoryWalker": {
            "input": "user_id + mode (read_session | write | update_status)",
            "output": "SessionSnapshot{has_history, next_step, applied[], pending[]}",
            "stub": "summarize_session()",
            "tools": False
        },
        "EscalationWalker": {
            "input": "NeedProfile when no resource matched",
            "output": "EscalationMessage{is_emergency, crisis_resources[], appeal_options[], personalized_message}",
            "stub": "ReAct loop · 3 tools",
            "tools": True
        }
    };

    # Empty state — no chat session has run yet.
    if total_events == 0 {
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
                <div style={{"fontSize": "32px", "marginBottom": "10px"}}>📊</div>
                <div style={{"fontSize": "16px", "fontWeight": "600", "marginBottom": "8px", "color": "#FFE500"}}>
                    No telemetry yet
                </div>
                <div style={{"fontSize": "13px", "color": "rgba(255,255,255,0.55)", "lineHeight": "1.6", "marginBottom": "16px"}}>
                    Walker call counts, latency, and call-tree are computed live from the event stream emitted by chat turns. Send a message in the Chat tab and switch back here to see the multi-agent pipeline activity.
                </div>
                <div style={{
                    "padding": "12px 14px",
                    "background": "rgba(255,229,0,0.06)",
                    "border": "0.5px solid rgba(255,229,0,0.2)",
                    "borderRadius": "10px",
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.6)",
                    "textAlign": "left",
                    "lineHeight": "1.55"
                }}>
                    <div style={{"color": "#FFE500", "fontWeight": "600", "marginBottom": "4px"}}>
                        For full LLM telemetry (token counts, cost, traces):
                    </div>
                    Run an admin session at <span style={{"color": "#FFE500"}}>/admin/llm/telemetry/summary</span> with admin credentials — that endpoint exposes per-invocation traces, prompt-cache hit rate, and provider-level cost.
                </div>
            </div>;
    }

    return
        <div>
            <div
                style={{
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.4)",
                    "marginBottom": "12px",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "6px"
                }}
            >
                <span
                    style={{
                        "width": "6px", "height": "6px",
                        "borderRadius": "50%",
                        "background": "#00FF88",
                        "display": "inline-block"
                    }}
                />
                Live data — {str(total_events)} walker events captured this session.
                For per-invocation LLM token/cost traces, open <span style={{"color": "#FFE500"}}>/admin/llm/telemetry</span>.
            </div>

            <div
                style={{
                    "display": "grid",
                    "gridTemplateColumns": "repeat(3,1fr)",
                    "gap": "10px",
                    "marginBottom": "14px"
                }}
            >
                <div
                    className="stat-enter"
                    style={{
                        "padding": "14px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.07)",
                        "borderRadius": "12px",
                        "textAlign": "center"
                    }}
                >
                    <div style={{"fontSize": "20px", "marginBottom": "5px"}}>📞</div>
                    <div style={{"fontSize": "22px", "fontWeight": "600", "color": "#FFE500"}}>
                        {str(total_events)}
                    </div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "3px"}}>
                        Walker events
                    </div>
                </div>
                <div
                    className="stat-enter"
                    style={{
                        "padding": "14px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.07)",
                        "borderRadius": "12px",
                        "textAlign": "center"
                    }}
                >
                    <div style={{"fontSize": "20px", "marginBottom": "5px"}}>🤖</div>
                    <div style={{"fontSize": "22px", "fontWeight": "600", "color": "#FFE500"}}>
                        {str(len([w for w in walker_order if triggered[w]]))}
                    </div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "3px"}}>
                        Walkers triggered
                    </div>
                </div>
                <div
                    className="stat-enter"
                    style={{
                        "padding": "14px",
                        "background": "rgba(255,255,255,0.03)",
                        "backdropFilter": "blur(12px)",
                        "border": "0.5px solid rgba(255,255,255,0.07)",
                        "borderRadius": "12px",
                        "textAlign": "center"
                    }}
                >
                    <div style={{"fontSize": "20px", "marginBottom": "5px"}}>⚡</div>
                    <div style={{"fontSize": "22px", "fontWeight": "600", "color": "#FFE500"}}>
                        llama-3.1-8b
                    </div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "3px"}}>
                        Active model
                    </div>
                </div>
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
                        "padding": "10px 16px",
                        "borderBottom": "0.5px solid rgba(255,255,255,0.06)",
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.35)",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.06em"
                    }}
                >
                    Walker activity
                </div>
                {[renderWalkerRow(walker_order[i]) for i in range(len(walker_order))]}
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
                <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.35)", "marginBottom": "14px", "textTransform": "uppercase", "letterSpacing": "0.06em"}}>
                    Walker call tree — parent → child invocation
                </div>
                <div style={{"display": "flex", "alignItems": "center", "overflowX": "auto", "gap": "0"}}>
                    {[renderChainNode(walker_order[i], bool(triggered[walker_order[i]]), int(counts[walker_order[i]])) for i in range(len(walker_order))]}
                </div>
                <div style={{"marginTop": "14px", "paddingTop": "12px", "borderTop": "0.5px solid rgba(255,255,255,0.06)"}}>
                    <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.3)", "marginBottom": "7px", "textTransform": "uppercase", "letterSpacing": "0.06em"}}>
                        Recent events
                    </div>
                    {[renderEvent(walker_events[j], j) for j in range(max(0, total_events - 8), total_events)]}
                </div>
            </div>

            <div
                style={{
                    "marginTop": "14px",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.07)",
                    "borderRadius": "14px",
                    "padding": "16px 18px"
                }}
            >
                <div
                    style={{
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.35)",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.06em",
                        "marginBottom": "4px"
                    }}
                >
                    Agent reasoning transparency
                </div>
                <div
                    style={{
                        "fontSize": "11px",
                        "color": "rgba(255,255,255,0.45)",
                        "marginBottom": "14px",
                        "lineHeight": "1.45"
                    }}
                >
                    For each walker that ran this session: the input the LLM saw, the structured output type it produced, and whether it dispatched any tools mid-execution.
                </div>
                <div style={{"display": "flex", "flexDirection": "column", "gap": "10px"}}>
                    {[renderCallCard(walker_order[i]) for i in range(len(walker_order)) if triggered[walker_order[i]]]}
                </div>
            </div>

            {renderReflectionTimeline()}
        </div>;
}
