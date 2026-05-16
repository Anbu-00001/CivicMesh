"""Async logic for ChatPane component."""

impl ChatPane.sendMessage -> None {
    if (not input_val.strip()) or is_loading {
        return;
    }
    user_text = input_val;
    input_val = "";
    messages = messages + [{"role": "user", "text": user_text, "walker": ""}];
    is_loading = True;
    active_walker = "IntakeWalker";
    on_walker_event({"walker": "IntakeWalker", "status": "running", "node": "root"});

    conversation = " ".join([str(m["text"]) for m in messages if str(m["role"]) in ["user", "bot"]]);

    active_walker = "IntakeWalker → EligibilityWalker";
    on_walker_event({"walker": "EligibilityWalker", "status": "running", "node": "NeedNode"});

    try {
        result = root spawn IntakeWalker(
            conversation=conversation,
            user_id=user_id
        );
        data = dict(result.reports[0]) if result.reports else {};

        if data {
            detected_language = str(data.get("language", "en"));
            profile_extracted = dict(data.get("profile", {}));

            active_walker = "NavigationWalker";
            on_walker_event({"walker": "NavigationWalker", "status": "running", "node": "ActionPlan"});

            elig = dict(data.get("eligibility_results", {}));
            bot_text = "";
            bot_walker = "";
            if elig.get("escalated", False) {
                esc = dict(elig.get("escalation", {}));
                bot_text = str(esc.get("personalized_message", "I found crisis resources. Let me connect you with immediate help."));
                bot_walker = "EscalationWalker";
            } else {
                outer_plan = dict(elig.get("action_plan", {}));
                plan_data = dict(outer_plan.get("action_plan", {}));
                step_list = list(plan_data.get("steps", []));
                step_count = len(step_list);
                eligible_count = int(elig.get("eligible_count", 0));
                bot_text = f"Found {eligible_count} resources you qualify for. Created a {step_count}-step plan. Go to Action Plan to see your next steps.";
                bot_walker = "NavigationWalker";
            }

            on_walker_event({"walker": "MemoryWalker", "status": "complete", "node": "ApplicationNode"});
            messages = messages + [{"role": "bot", "text": bot_text, "walker": bot_walker}];
        }
    } except Exception as _ex {
        messages = messages + [{"role": "bot", "text": "Something went wrong. Please try again.", "walker": "error"}];
    }

    is_loading = False;
    active_walker = "";
}

impl ChatPane.renderMessage(msg: dict, idx: int) -> JsxElement {
    is_user = str(msg["role"]) == "user";
    wname = str(msg.get("walker", ""));
    walker_colors = {
        "IntakeWalker": "#FFE500",
        "EligibilityWalker": "#4488FF",
        "NavigationWalker": "#00FF88",
        "MemoryWalker": "#FFB344",
        "EscalationWalker": "#FF4444",
        "system": "#FFE500"
    };
    wcolor = str(walker_colors.get(wname, "rgba(255,255,255,0.3)"));

    return
        <div
            key={idx}
            style={{
                "display": "flex",
                "justifyContent": ("flex-end" if is_user else "flex-start")
            }}
        >
            {(not is_user) and <div
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
                    "flexShrink": "0",
                    "marginRight": "8px",
                    "marginTop": "4px"
                }}
            >
                CM
            </div>}
            <div style={{"maxWidth": "78%"}}>
                {((not is_user) and wname) and <div
                    style={{
                        "fontSize": "10px",
                        "color": wcolor,
                        "marginBottom": "3px",
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "4px"
                    }}
                >
                    <span
                        style={{
                            "width": "4px",
                            "height": "4px",
                            "borderRadius": "50%",
                            "background": wcolor,
                            "display": "inline-block"
                        }}
                    />
                    {wname}
                </div>}
                <div
                    style={{
                        "padding": "10px 14px",
                        "borderRadius": ("16px 16px 4px 16px" if is_user else "4px 16px 16px 16px"),
                        "background": ("#FFE500" if is_user else "rgba(255,255,255,0.06)"),
                        "color": ("#0A0A0A" if is_user else "#FFFFFF"),
                        "fontSize": "14px",
                        "lineHeight": "1.55",
                        "border": ("none" if is_user else "0.5px solid rgba(255,255,255,0.09)"),
                        "borderLeft": ("none" if (is_user or (not wname) or wname == "system") else f"2px solid {wcolor}")
                    }}
                >
                    {msg["text"]}
                </div>
            </div>
        </div>;
}
