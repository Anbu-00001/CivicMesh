"""Async logic for ChatPane component."""

impl ChatPane.walkerColor(walker_name: str) -> str {
    colors = {
        "IntakeWalker": "#FFE500",
        "EligibilityWalker": "#4488FF",
        "NavigationWalker": "#00FF88",
        "MemoryWalker": "#FFB344",
        "EscalationWalker": "#FF4444",
        "system": "#FFE500"
    };
    return colors.get(walker_name, "rgba(255,255,255,0.3)");
}


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

    bot_text = "";
    bot_walker = "";
    lang_str = "en";
    profile_obj: Any = None;

    try {
        result = await root spawn IntakeWalker(
            conversation=conversation,
            user_id=user_id
        );
        # Use a safe-by-default container so missing keys return undefined
        # rather than throwing JS TypeErrors that bypass Jac except blocks.
        data: Any = (result.reports[0] if (result.reports and len(result.reports) > 0) else {}) or {};

        raw_lang = data["language"];
        if raw_lang { lang_str = str(raw_lang); }

        raw_profile = data["profile"];
        if raw_profile { profile_obj = raw_profile; }

        active_walker = "NavigationWalker";
        on_walker_event({"walker": "NavigationWalker", "status": "running", "node": "ActionPlan"});

        raw_elig = data["eligibility_results"];
        elig: Any = raw_elig if raw_elig else {};

        escalated = bool(elig["escalated"]);
        if escalated {
            esc_raw = elig["escalation"];
            esc: Any = esc_raw if esc_raw else {};
            msg_raw = esc["personalized_message"];
            if msg_raw {
                bot_text = str(msg_raw);
            } else {
                bot_text = "I found crisis resources. Let me connect you with immediate help.";
            }
            bot_walker = "EscalationWalker";
        } else {
            step_count = 0;
            eligible_count = 0;
            ec_raw = elig["eligible_count"];
            if ec_raw { eligible_count = int(ec_raw); }
            plan_top_raw = elig["action_plan"];
            plan_top: Any = plan_top_raw if plan_top_raw else {};
            plan_inner_raw = plan_top["action_plan"];
            plan_inner: Any = plan_inner_raw if plan_inner_raw else {};
            steps_raw = plan_inner["steps"];
            if steps_raw {
                step_list: list = list(steps_raw);
                step_count = len(step_list);
            }
            bot_text = f"Found {eligible_count} resources you qualify for. Created a {step_count}-step plan. Go to Action Plan to see your next steps.";
            bot_walker = "NavigationWalker";
        }

        on_walker_event({"walker": "MemoryWalker", "status": "complete", "node": "ApplicationNode"});
    } except Exception as _ex {
        bot_text = "Something went wrong. Please try again.";
        bot_walker = "error";
    }

    detected_language = lang_str;
    profile_extracted = profile_obj;
    if bot_text {
        messages = messages + [{"role": "bot", "text": bot_text, "walker": bot_walker}];
    }

    is_loading = False;
    active_walker = "";
}

impl ChatPane.renderMessage(msg: dict, idx: int, is_last: bool) -> JsxElement {
    is_user = str(msg["role"]) == "user";
    wname = str(msg.get("walker", ""));
    is_last_bot = is_last and (not is_user);
    bubble_class = "msg-typewriter" if is_last_bot else "";
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
            className="msg-enter"
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
                    className={bubble_class}
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
