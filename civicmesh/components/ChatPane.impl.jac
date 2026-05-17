"""Async logic for ChatPane component."""

impl ChatPane.detectIntent(text: str) -> str {
    # Light keyword classification that biases follow-up suggestions toward
    # the user's emotional register and asking style. No LLM call — just
    # scans the raw user prompt for signal words. Returns one of:
    #   "crisis"     — imminent danger, eviction, abuse, homelessness
    #   "exploring"  — open-ended questions, "tell me about", "what is"
    #   "logistics"  — procedural asks about forms, documents, steps
    #   "general"    — anything else (default)
    t = text.lower();
    crisis_keywords = [
        "emergency", "immediate", "tonight", "right now", "dying", "homeless",
        "eviction", "evicted", "abuse", "violence", "danger", "scared",
        "crisis", "suicide", "hurt", "hurting", "starving", "no food",
        "kicked out", "domestic", "shelter tonight", "no money"
    ];
    explore_keywords = [
        "what is", "what about", "tell me", "can you explain", "how does",
        "what kind", "do you have", "are there", "what other", "more info",
        "i'm wondering", "curious about"
    ];
    logistics_keywords = [
        "documents", "paperwork", "form", "apply", "application", "deadline",
        "next step", "how do i", "where do i", "what do i need", "phone number",
        "address", "appointment", "office hours", "qualify", "eligible"
    ];
    for kw in crisis_keywords {
        if kw in t { return "crisis"; }
    }
    for kw in explore_keywords {
        if kw in t { return "exploring"; }
    }
    for kw in logistics_keywords {
        if kw in t { return "logistics"; }
    }
    return "general";
}

impl ChatPane.generateSuggestions(profile: Any, escalated: bool, bot_walker: str, user_text: str) -> list {
    # Two-axis lookup: emotional intent × need category.
    # - Intent is detected from the user's last message (crisis/exploring/
    #   logistics/general) so suggestions track the user's mood.
    # - Category branches into adjacent domains the agent can help with.
    cat = "";
    if profile {
        c_raw = profile["category"];
        if c_raw { cat = str(c_raw).lower(); }
    }
    intent = detectIntent(user_text);

    # CRISIS — user used urgent / danger language. Surface immediate-help routes.
    if intent == "crisis" or escalated {
        if cat == "housing" {
            return [
                "I'm being evicted tonight — what shelter can I reach right now?",
                "Are there emergency motel vouchers I qualify for?",
                "Who do I call for a domestic-violence safe house?"
            ];
        }
        if cat == "food" {
            return [
                "My kids haven't eaten today — is there a food bank open now?",
                "Can I get an emergency SNAP advance this week?",
                "Are there meal-delivery programs for emergencies?"
            ];
        }
        if cat == "healthcare" {
            return [
                "I'm in a mental-health crisis — what hotline should I call?",
                "Is there a free emergency clinic open tonight?",
                "How do I get free prescription assistance immediately?"
            ];
        }
        if cat == "legal" {
            return [
                "I have a court date this week — who can defend me for free?",
                "How fast can a legal aid org take my case?",
                "What do I do if I can't appear in court tomorrow?"
            ];
        }
        # Generic crisis fallback
        return [
            "I'm in immediate danger — what crisis lines should I call?",
            "What 24/7 emergency resources are available in my area?",
            "Can you connect me with a crisis counselor right now?"
        ];
    }

    # LOGISTICS — user is asking procedural questions. Drill into the plan.
    if intent == "logistics" {
        if cat == "housing" {
            return [
                "What documents do I need to apply for Section 8?",
                "How long does the housing application typically take?",
                "Can I apply at multiple housing programs at once?"
            ];
        }
        if cat == "food" {
            return [
                "Walk me through the SNAP application step-by-step.",
                "What income documentation do I need for WIC?",
                "How do I check the status of a pending food-benefit case?"
            ];
        }
        if cat == "healthcare" {
            return [
                "How do I enroll in Medicaid given my income?",
                "What do I bring to a free-clinic intake appointment?",
                "Are there sliding-scale dental clinics nearby?"
            ];
        }
        if cat == "legal" {
            return [
                "What documents should I gather before my legal-aid intake?",
                "How do I request a continuance on my court date?",
                "Can you explain my rights as a tenant facing eviction?"
            ];
        }
        return [
            "What documents do I need for the first step?",
            "How long does the application process usually take?",
            "Can I apply to more than one program at the same time?"
        ];
    }

    # EXPLORING — user is open-ended, asking what else exists. Show adjacent.
    if intent == "exploring" {
        if cat == "housing" {
            return [
                "What food assistance programs might help my family too?",
                "Are there utility-bill help programs alongside housing aid?",
                "What legal aid is available for renters in my situation?"
            ];
        }
        if cat == "food" {
            return [
                "What housing help is available for low-income families?",
                "Are there free childcare or after-school food programs?",
                "How do I get on the SNAP and WIC programs together?"
            ];
        }
        if cat == "healthcare" {
            return [
                "What mental-health resources exist beyond crisis lines?",
                "Are there free dental or vision clinics for adults?",
                "How does Medicaid coverage interact with free clinics?"
            ];
        }
        if cat == "legal" {
            return [
                "What immigration legal aid is available?",
                "Are there self-help legal clinics for tenants?",
                "How does pro-bono representation actually work?"
            ];
        }
        return [
            "What kinds of resources do you cover overall?",
            "Can you tell me about food, housing, and legal aid together?",
            "Which programs have the shortest wait times?"
        ];
    }

    # GENERAL — light category-aware nudge
    if cat == "housing" {
        return [
            "Do I qualify for food assistance too?",
            "What documents do I need for the first step?",
            "Are there any legal aid programs for renters?"
        ];
    }
    if cat == "food" {
        return [
            "Can you help me with housing assistance?",
            "What about children's nutrition programs (WIC)?",
            "How do I apply for SNAP step-by-step?"
        ];
    }
    if cat == "healthcare" {
        return [
            "What about mental health resources?",
            "Are there free clinics in my area?",
            "How do I get free prescription assistance?"
        ];
    }
    if cat == "legal" {
        return [
            "What about emergency housing in case I'm evicted?",
            "Can I get legal aid for immigration too?",
            "What documents should I gather before the appointment?"
        ];
    }

    # Cold-start fallback
    return [
        "I need help with housing.",
        "I need food assistance for my family.",
        "I need legal help to avoid eviction."
    ];
}


impl ChatPane.isLowSignal(text: str) -> bool {
    # Cheap client-side gibberish detector. The LLM-based stubs happily
    # hallucinate a "housing/immediate" need out of any 6-letter scribble,
    # so we gate the walker chain on a few heuristic checks first.
    s = text.strip();
    if len(s) < 8 {
        return True;
    }
    word_count = 0;
    parts = s.split(" ");
    for p in parts {
        if len(p) > 0 { word_count = word_count + 1; }
    }
    if word_count < 2 and len(s) < 16 {
        return True;
    }

    # Vowel ratio check. Real English/Spanish/most languages run ~35-45%
    # vowels. Random keyboard mashing typically lands well under 20%.
    vowels = "aeiouAEIOU";
    vowel_count = 0;
    letter_count = 0;
    n = len(s);
    i = 0;
    while i < n {
        c = s[i];
        is_letter = False;
        # ASCII letter check
        if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") {
            is_letter = True;
        }
        if is_letter {
            letter_count = letter_count + 1;
            if c in vowels {
                vowel_count = vowel_count + 1;
            }
        }
        i = i + 1;
    }
    if letter_count >= 8 {
        # Vowel ratio < 18% is very unlikely for real prose.
        if (vowel_count * 100) < (letter_count * 18) {
            return True;
        }
    }
    return False;
}

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


impl ChatPane.sendMessage(text_override: str = "") -> None {
    if is_loading {
        return;
    }
    # When a suggestion chip is clicked we pass the prompt directly via
    # text_override (closure-safe). Keyboard input falls back to input_val.
    effective = text_override if text_override else input_val;
    if not effective.strip() {
        return;
    }
    user_text = effective;
    input_val = "";
    # Accumulate locally so the final setMessages() call carries both the user
    # message and the bot reply. Without this, React closure staleness causes
    # the second setMessages() to overwrite the first (user msg disappears).
    new_messages = messages + [{"role": "user", "text": user_text, "walker": ""}];
    messages = new_messages;

    # Short-circuit on gibberish/low-signal input — don't burn an LLM call
    # extracting a fake "housing/immediate" need from keyboard noise.
    if isLowSignal(user_text) {
        clarify = "I didn't quite catch that. Could you tell me what kind of help you're looking for? For example: housing, food, healthcare, or legal aid — and a bit about your situation (family size, income, city) helps me match real resources.";
        new_messages = new_messages + [{"role": "bot", "text": clarify, "walker": "system"}];
        messages = new_messages;
        return;
    }

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
    escalated: bool = False;

    # Build a structured reasoning trace as the walker chain executes.
    # Each step is shown beneath the bot reply so the user can see HOW
    # the agent arrived at its conclusion (real agentic transparency).
    trace_steps: list = [];

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

        # Trace step 1: language detection
        trace_steps = trace_steps + [{
            "walker": "IntakeWalker",
            "title": "Detected language",
            "value": lang_str.upper(),
            "detail": "Routing the rest of the chain through " + lang_str.upper() + "-language prompts."
        }];

        # Trace step 2: profile extraction
        pc = "";
        pu = "";
        pd = "";
        if profile_obj {
            pc_raw = profile_obj["category"];
            pu_raw = profile_obj["urgency"];
            pd_raw = profile_obj["details"];
            if pc_raw { pc = str(pc_raw); }
            if pu_raw { pu = str(pu_raw); }
            if pd_raw { pd = str(pd_raw); }
        }
        trace_steps = trace_steps + [{
            "walker": "IntakeWalker",
            "title": "Extracted NeedProfile",
            "value": (pc + " · " + pu) if pc else "no profile",
            "detail": pd if pd else "No additional details extracted."
        }];

        active_walker = "NavigationWalker";
        local_events = local_events + [{"walker": "NavigationWalker", "status": "running", "node": "ActionPlan"}];
        on_walker_event(local_events);

        raw_elig = data["eligibility_results"];
        elig: Any = raw_elig if raw_elig else {};

        # Trace step 3: eligibility scoring
        elig_count = 0;
        poss_count = 0;
        top_match_summary = "";
        ec_raw = elig["eligible_count"];
        pcz_raw = elig["possible_count"];
        if ec_raw { elig_count = int(ec_raw); }
        if pcz_raw { poss_count = int(pcz_raw); }
        top_matches_raw = elig["top_matches"];
        if top_matches_raw {
            tms: list = list(top_matches_raw);
            top_parts: list = [];
            ti = 0;
            while ti < len(tms) and ti < 3 {
                tm: Any = tms[ti];
                tm_name = str(tm["resource"]) if tm["resource"] else "?";
                tm_score = str(tm["score"]) if tm["score"] else "0";
                top_parts = top_parts + [tm_name + " (" + tm_score + ")"];
                ti = ti + 1;
            }
            top_match_summary = " · ".join(top_parts);
        }
        trace_steps = trace_steps + [{
            "walker": "EligibilityWalker",
            "title": "Scored resources via check_eligibility()",
            "value": str(elig_count) + " eligible · " + str(poss_count) + " possible",
            "detail": top_match_summary if top_match_summary else "No resources scored above the eligibility threshold for this profile."
        }];

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

            # Trace step 4 (escalation branch): ReAct tools
            iter_count = 0;
            crisis_n = 0;
            appeal_n = 0;
            is_emerg = False;
            iter_raw = esc["iterations_used"];
            if iter_raw { iter_count = int(iter_raw); }
            cr_raw = esc["crisis_resources"];
            if cr_raw {
                cr_list: list = list(cr_raw);
                crisis_n = len(cr_list);
            }
            ap_raw = esc["appeal_options"];
            if ap_raw {
                ap_list: list = list(ap_raw);
                appeal_n = len(ap_list);
            }
            ie_raw = esc["is_emergency"];
            if ie_raw { is_emerg = bool(ie_raw); }
            tool_detail = "Invoked tools: check_emergency_resources() → "
                + str(crisis_n) + " crisis lines · find_appeal_orgs() → "
                + str(appeal_n) + " appeal paths · assess_safety_risk() → "
                + ("EMERGENCY" if is_emerg else "non-emergency");
            trace_steps = trace_steps + [{
                "walker": "EscalationWalker",
                "title": "Composed escalation via ReAct loop (" + str(iter_count) + " iterations)",
                "value": "is_emergency: " + ("true" if is_emerg else "false"),
                "detail": tool_detail
            }];
        } else {
            step_count = 0;
            eligible_count = 0;
            ec2_raw = elig["eligible_count"];
            if ec2_raw { eligible_count = int(ec2_raw); }
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

            # Trace step 4 (navigation branch): plan generation
            plan_summary = "";
            ps_raw = plan_inner["summary"];
            if ps_raw { plan_summary = str(ps_raw); }
            trace_steps = trace_steps + [{
                "walker": "NavigationWalker",
                "title": "Generated ActionPlan via generate_action_plan()",
                "value": str(step_count) + "-step plan",
                "detail": plan_summary if plan_summary else "Sequenced eligible resources into ordered ApplicationNodes persisted on applied_to edges."
            }];
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

    # Generate contextual, intent-aware follow-up suggestions in English.
    # Intent (crisis / exploring / logistics / general) is detected from
    # the user's last message so suggestions track emotional register.
    suggestions: list = generateSuggestions(profile_obj, escalated, bot_walker, user_text);

    # Translate the bot reply + suggestion chips into the user's detected
    # language so the UX feels native. The translate stub passes through
    # unchanged for English; for any other language it makes a single batch
    # LLM call (one call total for the whole turn, not one per chip).
    lang_lower = lang_str.lower();
    if bot_text and lang_lower and lang_lower != "en" and lang_lower != "english" {
        try {
            payload: list[str] = [bot_text] + [str(suggestions[ti]) for ti in range(len(suggestions))];
            tr_result = await root spawn TranslateWalker(
                texts=payload,
                target_language=lang_str
            );
            tr_reports = tr_result.reports;
            tr_n = len(tr_reports) if tr_reports else 0;
            if tr_n > 0 {
                tr_data: Any = tr_reports[tr_n - 1];
                tr_list_raw = tr_data["translated"] if tr_data else None;
                if tr_list_raw {
                    tr_list: list = list(tr_list_raw);
                    if len(tr_list) == len(payload) {
                        bot_text = str(tr_list[0]);
                        new_sugs: list = [];
                        si = 1;
                        while si < len(tr_list) {
                            new_sugs = new_sugs + [str(tr_list[si])];
                            si = si + 1;
                        }
                        suggestions = new_sugs;
                    }
                }
            }
        } except Exception as _ex {
            # Translation failed — keep English. Better than no reply.
        }
    }

    if bot_text {
        # Use the local accumulator (new_messages) instead of the stale
        # closure `messages` so the user's prompt isn't dropped.
        new_messages = new_messages + [{
            "role": "bot",
            "text": bot_text,
            "walker": bot_walker,
            "trace": trace_steps,
            "suggestions": suggestions
        }];
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

    # Pull trace + suggestions if present (bot replies only)
    trace_raw: list = list(msg["trace"]) if msg["trace"] else [];
    trace_n = len(trace_raw);
    has_trace = (not is_user) and (trace_n > 0);
    trace_open = (idx == open_trace_idx);
    sugg_raw: list = list(msg["suggestions"]) if msg["suggestions"] else [];
    sugg_n = len(sugg_raw);
    has_suggestions = (not is_user) and (sugg_n > 0) and is_last;

    return
        <div
            key={idx}
            className="msg-enter"
            style={{
                "display": "flex",
                "flexDirection": "column",
                "alignItems": ("flex-end" if is_user else "flex-start")
            }}
        >
            <div style={{"display": "flex", "alignItems": "flex-start", "width": "100%", "justifyContent": ("flex-end" if is_user else "flex-start")}}>
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

                    {has_trace and <button
                        onClick={lambda _e: MouseEvent {
                            open_trace_idx = (-1 if (idx == open_trace_idx) else idx);
                        }}
                        style={{
                            "marginTop": "6px",
                            "padding": "4px 10px",
                            "fontSize": "10px",
                            "background": "rgba(255,229,0,0.06)",
                            "border": "0.5px solid rgba(255,229,0,0.25)",
                            "color": "#FFE500",
                            "borderRadius": "6px",
                            "cursor": "pointer",
                            "display": "inline-flex",
                            "alignItems": "center",
                            "gap": "4px"
                        }}
                    >
                        {("▾ Hide agent reasoning" if trace_open else "▸ Show agent reasoning (" + str(trace_n) + " steps)")}
                    </button>}

                    {(has_trace and trace_open) and <div
                        style={{
                            "marginTop": "8px",
                            "padding": "10px 12px",
                            "background": "rgba(0,0,0,0.35)",
                            "border": "0.5px solid rgba(255,255,255,0.08)",
                            "borderRadius": "10px",
                            "fontSize": "11px",
                            "lineHeight": "1.55"
                        }}
                    >
                        {[renderTraceStep(trace_raw[ti], ti) for ti in range(trace_n)]}
                    </div>}

                    {has_suggestions and <div
                        style={{
                            "marginTop": "10px",
                            "display": "flex",
                            "flexDirection": "column",
                            "gap": "5px"
                        }}
                    >
                        <div style={{
                            "fontSize": "10px",
                            "color": "rgba(255,255,255,0.4)",
                            "textTransform": "uppercase",
                            "letterSpacing": "0.06em",
                            "marginBottom": "2px"
                        }}>
                            Suggested follow-ups
                        </div>
                        <div style={{"display": "flex", "flexWrap": "wrap", "gap": "6px"}}>
                            {[renderSuggestionChip(str(sugg_raw[si])) for si in range(sugg_n)]}
                        </div>
                    </div>}
                </div>
            </div>
        </div>;
}

impl ChatPane.renderTraceStep(step: Any, idx: int) -> JsxElement {
    title = str(step["title"]) if step["title"] else "";
    value = str(step["value"]) if step["value"] else "";
    detail = str(step["detail"]) if step["detail"] else "";
    swk = str(step["walker"]) if step["walker"] else "";
    swc = walkerColor(swk);
    return
        <div
            key={str(idx)}
            style={{
                "padding": "6px 0",
                "borderBottom": ("0.5px solid rgba(255,255,255,0.05)" if idx < 99 else "none"),
                "display": "flex",
                "gap": "10px"
            }}
        >
            <div style={{"minWidth": "20px", "color": "rgba(255,255,255,0.3)", "fontSize": "10px"}}>
                {str(idx + 1) + "."}
            </div>
            <div style={{"flex": "1"}}>
                <div style={{"display": "flex", "alignItems": "center", "gap": "6px", "flexWrap": "wrap"}}>
                    <span style={{"fontSize": "9px", "padding": "1px 6px", "borderRadius": "8px", "background": swc + "15", "color": swc, "border": "0.5px solid " + swc + "40", "fontWeight": "600", "letterSpacing": "0.02em"}}>
                        {swk}
                    </span>
                    <span style={{"color": "rgba(255,255,255,0.85)", "fontWeight": "500"}}>{title}</span>
                </div>
                <div style={{"color": "#FFE500", "fontSize": "11px", "marginTop": "2px", "fontFamily": "ui-monospace, monospace"}}>
                    {value}
                </div>
                <div style={{"color": "rgba(255,255,255,0.5)", "fontSize": "11px", "marginTop": "2px"}}>
                    {detail}
                </div>
            </div>
        </div>;
}

impl ChatPane.renderSuggestionChip(text: str) -> JsxElement {
    return
        <button
            key={text}
            onClick={lambda _e: MouseEvent { sendMessage(text); }}
            disabled={is_loading}
            style={{
                "padding": "6px 11px",
                "fontSize": "11px",
                "background": "rgba(255,255,255,0.04)",
                "border": "0.5px solid rgba(255,229,0,0.25)",
                "color": "rgba(255,229,0,0.85)",
                "borderRadius": "16px",
                "cursor": "pointer",
                "lineHeight": "1.4",
                "textAlign": "left",
                "transition": "all 0.15s ease"
            }}
        >
            {text}
        </button>;
}
