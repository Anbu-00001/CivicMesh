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
    # Accumulate locally so the final setMessages() call carries both the user
    # message and the bot reply. Without this, React closure staleness causes
    # the second setMessages() to overwrite the first (user msg disappears).
    new_messages = messages + [{"role": "user", "text": user_text, "walker": ""}];
    messages = new_messages;
    is_loading = True;
    active_walker = "IntakeWalker";

    # Accumulate walker events locally and ALWAYS pass the full list to the
    # parent. ClientApp.pushWalkerEvent does a full replace (not append) so
    # this avoids the closure-staleness problem when many events fire
    # synchronously in one chat turn.
    local_events: list = list(walker_events) if walker_events else [];
    local_events = local_events + [{"walker": "IntakeWalker", "status": "running", "node": "root"}];
    on_walker_event(local_events);

    # Send only the latest user prompt to IntakeWalker. The walker is a
    # stateless intent extractor — joining the whole transcript pollutes
    # context with previous bot replies and makes follow-up answers repeat.
    conversation = user_text;

    active_walker = "IntakeWalker → EligibilityWalker";
    local_events = local_events + [{"walker": "EligibilityWalker", "status": "running", "node": "NeedNode"}];
    on_walker_event(local_events);

    bot_text = "";
    bot_walker = "";
    lang_str = "en";
    profile_obj: Any = None;

    try {
        result = await root spawn IntakeWalker(
            conversation=conversation,
            user_id=user_id
        );
        # Walker chain emits reports inner-first; the outermost IntakeWalker
        # payload (which carries `language`, `profile`, `eligibility_results`)
        # is the LAST entry in `reports`. Safe-by-default container so missing
        # keys return undefined instead of throwing JS TypeErrors that bypass
        # Jac except blocks.
        report_count = len(result.reports) if result.reports else 0;
        data: Any = (result.reports[report_count - 1] if report_count > 0 else {}) or {};

        raw_lang = data["language"];
        if raw_lang { lang_str = str(raw_lang); }

        raw_profile = data["profile"];
        if raw_profile { profile_obj = raw_profile; }

        active_walker = "NavigationWalker";
        local_events = local_events + [{"walker": "NavigationWalker", "status": "running", "node": "ActionPlan"}];
        on_walker_event(local_events);

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

        # Final event for the chain — bot_walker tells us which walker
        # actually produced the user-visible reply (EscalationWalker or
        # NavigationWalker), so record that as the terminal step.
        final_walker = bot_walker if bot_walker else "MemoryWalker";
        local_events = local_events + [{"walker": final_walker, "status": "complete", "node": "ApplicationNode"}];
        on_walker_event(local_events);
    } except Exception as _ex {
        bot_text = "Something went wrong. Please try again.";
        bot_walker = "error";
    }

    detected_language = lang_str;
    profile_extracted = profile_obj;
    if bot_text {
        # Use the local accumulator (new_messages) instead of the stale
        # closure `messages` so the user's prompt isn't dropped.
        new_messages = new_messages + [{"role": "bot", "text": bot_text, "walker": bot_walker}];
        messages = new_messages;
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
