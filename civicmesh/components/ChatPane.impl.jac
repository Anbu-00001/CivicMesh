"""ChatPane implementation: turn loop, background narration, result rendering.

jac-client notes that shape this file:
  * Each compiled module gets its own copy of the Jac exception classes, so a
    rejected walker call never matches a local `except Exception`. safeSpawn
    turns the rejection into a value at the promise level.
  * "\\n" inside client string literals compiles to a literal backslash-n, so
    no client code splits on newlines: server text renders with pre-wrap.
  * Background narration mutates the `narrations` object in place and bumps
    `narr_tick`, avoiding stale-closure overwrites of `messages`.
"""

impl ChatPane.safeSpawn(walker_name: str, fields: dict) -> Any {
    return await jacSpawn(walker_name, "", fields).catch(
        lambda err: Any -> dict { return {"reports": [], "spawn_error": str(err)}; }
    );
}

impl ChatPane.fmtMs(ms: float) -> str {
    v = Number(ms) if ms else 0.0;
    if v >= 1000.0 {
        return (v / 1000.0).toFixed(1) + " s";
    }
    if v >= 10.0 {
        return str(Math.round(v)) + " ms";
    }
    return v.toFixed(1) + " ms";
}

impl ChatPane.tierStyle(tier: str) -> dict {
    if tier == "likely" { return {"label": "Likely eligible", "color": "#00E08A", "bg": "rgba(0,224,138,0.12)"}; }
    if tier == "possible" { return {"label": "Possible", "color": "#5AA2FF", "bg": "rgba(90,162,255,0.12)"}; }
    if tier == "needs_info" { return {"label": "Needs info", "color": "#FFB344", "bg": "rgba(255,179,68,0.12)"}; }
    return {"label": "Unlikely", "color": "rgba(255,255,255,0.45)", "bg": "rgba(255,255,255,0.06)"};
}

impl ChatPane.resetCase -> None {
    profile_ctx = {};
    pending_question = "";
    messages = messages + [{
        "role": "bot", "kind": "text", "id": "reset-" + str(Math.random()),
        "text": "New case started — nothing from the previous conversation is carried over. What's going on?",
        "suggestions": []
    }];
}

impl ChatPane.spansToEvents(spans: list) -> list {
    names = {
        "intake.parse": ["IntakeWalker", "root"],
        "chat understand_message": ["IntakeWalker", "root"],
        "EligibilityWalker score": ["EligibilityWalker", "NeedNode"],
        "NavigationWalker plan": ["NavigationWalker", "ApplicationNode"],
        "PathfinderWalker yen_k_shortest": ["PathfinderWalker", "ResourceNode"],
        "EscalationWalker crisis_route": ["EscalationWalker", "PersonNode"],
        "reflexion.critique": ["CritiqueWalker", "SessionInsight"]
    };
    out: list = [];
    for sp in spans {
        hit = names[sp["name"]];
        if hit {
            out = out + [{"walker": hit[0], "status": "complete", "node": hit[1], "ms": sp["duration_ms"]}];
        }
    }
    return out;
}

impl ChatPane.sendMessage(text_override: str = "", answering: str = "") -> None {
    if is_loading { return; }
    effective = text_override if text_override else input_val;
    if not effective.strip() { return; }
    user_text = effective;
    input_val = "";
    ans = answering if answering else pending_question;
    user_msg = {"role": "user", "kind": "text", "id": "u" + str(Math.random()), "text": user_text, "evidence": []};
    new_messages = messages + [user_msg];
    messages = new_messages;
    is_loading = True;

    t0 = window.performance.now();
    res = await safeSpawn("IntakeWalker", {
        "conversation": user_text,
        "user_id": user_id,
        "prior": profile_ctx if profile_ctx else {},
        "answering": ans
    });
    rtt = window.performance.now() - t0;

    reps = res["reports"];
    n = len(reps) if reps else 0;
    data: Any = reps[n - 1] if n > 0 else None;
    if res["spawn_error"] or (not data) or (not data["trace"]) {
        new_messages = new_messages + [{"role": "bot", "kind": "error", "id": "e" + str(Math.random()), "text": "I couldn't reach the server just now. Please try again in a moment."}];
        messages = new_messages;
        is_loading = False;
        return;
    }

    user_msg["evidence"] = data["evidence"] if data["evidence"] else [];
    bot_id = "b" + str(Math.random());
    new_messages = new_messages + [{"role": "bot", "kind": "result", "id": bot_id, "data": data, "rtt_ms": rtt}];
    messages = new_messages;
    profile_ctx = data["profile"];
    q = data["question"];
    pending_question = str(q["key"]) if (q and q["key"]) else "";
    last_trace = data["trace"];
    on_walker_event(spansToEvents(list(data["trace"]["spans"])));
    is_loading = False;

    llm = data["llm"];
    if llm and llm["narrate"] {
        narrate(bot_id, data, user_text);
    }
}

impl ChatPane.narrate(msg_id: str, data: Any, user_text: str) -> None {
    narrations[msg_id] = {"status": "pending"};
    narr_tick = Math.random();
    t0 = window.performance.now();
    res = await safeSpawn("NarrateWalker", {
        "user_message": user_text,
        "language": data["language"],
        "facts": data["facts"],
        "chips": data["chips"] if data["chips"] else []
    });
    ms = window.performance.now() - t0;
    out = {"status": "failed", "ms": ms, "error": ""};
    reps = res["reports"];
    if reps and len(reps) > 0 {
        r = reps[len(reps) - 1];
        if r and r["ok"] {
            out = {"status": "ok", "message": r["message"], "chips": r["chips"], "ms": ms, "server_ms": r["latency_ms"]};
        } elif r {
            out["error"] = str(r["error"]) if r["error"] else "no narration";
        }
    } elif res["spawn_error"] {
        out["error"] = "server unreachable";
    }
    narrations[msg_id] = out;
    narr_tick = Math.random();
}

impl ChatPane.renderRich(text: str) -> JsxElement {
    parts = str(text).split("**");
    return
        <div className="cm-rich">
            {[(<strong key={"b" + str(i)}>{parts[i]}</strong>) if (i % 2 == 1) else (<span key={"s" + str(i)}>{parts[i]}</span>) for i in range(len(parts))]}
        </div>;
}

impl ChatPane.renderUserText(text: str, evidence: list) -> JsxElement {
    t = str(text);
    segs: list = [];
    pos = 0;
    for e in evidence {
        s0 = int(e["start"]);
        e0 = int(e["end"]);
        if s0 < pos or e0 > len(t) { continue; }
        if s0 > pos {
            segs = segs + [{"t": t.substring(pos, s0), "f": "", "v": ""}];
        }
        segs = segs + [{"t": t.substring(s0, e0), "f": str(e["field"]), "v": str(e["value"])}];
        pos = e0;
    }
    if pos < len(t) {
        segs = segs + [{"t": t.substring(pos), "f": "", "v": ""}];
    }
    return
        <span>
            {[(<mark key={"h" + str(i)} className={"cm-hl cm-hl-" + segs[i]["f"]} title={segs[i]["f"] + ": " + segs[i]["v"]}>{segs[i]["t"]}</mark>) if segs[i]["f"] else (<span key={"t" + str(i)}>{segs[i]["t"]}</span>) for i in range(len(segs))]}
        </span>;
}

impl ChatPane.renderChip(label: str, payload: str, answering: str) -> JsxElement {
    return
        <button
            key={"chip-" + label}
            className={("cm-chip cm-chip-answer" if answering else "cm-chip")}
            onClick={lambda _e: MouseEvent { sendMessage(payload, answering); }}
            disabled={is_loading}
        >
            {label}
        </button>;
}

impl ChatPane.renderQuickReplies(q: Any, lang: str) -> JsxElement {
    key = str(q["key"]);
    es = lang == "es";
    opts: list = [];
    if YES_NO_KEYS.includes(key) {
        opts = [["Sí" if es else "Yes", "sí" if es else "yes"], ["No", "no"]];
    } elif key == "income" {
        if es {
            opts = [["Menos de $1,000/mes", "unos $800 al mes"], ["$1,000–2,000/mes", "unos $1,500 al mes"], ["$2,000–3,000/mes", "unos $2,500 al mes"], ["Más de $3,000/mes", "unos $3,500 al mes"], ["Sin ingresos", "no tengo ingresos"]];
        } else {
            opts = [["Under $1,000/mo", "about $800 a month"], ["$1,000–2,000/mo", "about $1,500 a month"], ["$2,000–3,000/mo", "about $2,500 a month"], ["Over $3,000/mo", "about $3,500 a month"], ["No income", "no income"]];
        }
    } elif key == "household" {
        if es {
            opts = [["Solo yo", "vivo sola"], ["2", "somos 2"], ["3", "somos 3"], ["4", "somos 4"], ["5+", "somos 5"]];
        } else {
            opts = [["Just me", "just me"], ["2", "household of 2"], ["3", "household of 3"], ["4", "household of 4"], ["5+", "household of 5"]];
        }
    } elif key == "citizenship" {
        if es {
            opts = [["Ciudadano/a", "soy ciudadano"], ["Residente permanente", "soy residente permanente"], ["Sin papeles", "estoy sin papeles"]];
        } else {
            opts = [["U.S. citizen", "I'm a US citizen"], ["Green card / refugee", "I have a green card"], ["Not a citizen", "I'm undocumented"]];
        }
    }
    return
        <div className="cm-question">
            <div className="cm-question-text">
                <span className="cm-q-mark">?</span>
                <span>{str(q["text"])}</span>
                {Number(q["affects"]) > 0 and <span className="cm-q-gain">{("afecta " if es else "affects ") + str(q["affects"]) + (" programas" if es else " matches")}</span>}
            </div>
            {len(opts) > 0 and <div className="cm-chips">
                {[renderChip(str(o[0]), str(o[1]), key) for o in opts]}
            </div>}
        </div>;
}

impl ChatPane.renderMatchCard(m: Any, idx: int, j: int) -> JsxElement {
    ts = tierStyle(str(m["tier"]));
    card_key = str(idx) + ":" + str(j);
    is_open = open_key == card_key;
    pct = Math.round(Number(m["p_eligible"]) * 100);
    ap = m["approval"];
    mean = Math.round(Number(ap["mean"]) * 100);
    lo = Math.round(Number(ap["lo"]) * 100);
    hi = Math.round(Number(ap["hi"]) * 100);
    phone = str(m["contact_phone"]) if m["contact_phone"] else "";
    url = str(m["online_url"]) if m["online_url"] else "";
    crits: list = list(m["criteria"]) if m["criteria"] else [];
    cap = str(m["capacity"]);
    return
        <div key={"card-" + card_key} className="cm-card card-enter">
            <div className="cm-card-top">
                <span className="cm-tier" style={{"color": ts["color"], "background": ts["bg"]}}>{ts["label"]}</span>
                <span className="cm-cap">{("Open now" if cap == "open" else ("Waitlist" if cap == "waitlist" else cap)) + " · " + str(m["category"])}</span>
            </div>
            <div className="cm-card-name">{str(m["resource_name"])}</div>
            <div className="cm-meter-row">
                <span>Eligibility</span>
                <span style={{"color": ts["color"]}}>{str(pct) + "%"}</span>
            </div>
            <div className="cm-meter"><div style={{"width": str(pct) + "%", "background": ts["color"]}}/></div>
            <div className="cm-meter-row" title="Beta-Binomial posterior over recorded approvals/denials (capacity-informed prior)">
                <span>Approval odds</span>
                <span>{str(mean) + "% · 90% CI " + str(lo) + "–" + str(hi) + "%"}</span>
            </div>
            <div className="cm-ci">
                <div className="cm-ci-band" style={{"left": str(lo) + "%", "width": str(hi - lo) + "%"}}/>
                <div className="cm-ci-mean" style={{"left": str(mean) + "%"}}/>
            </div>
            {m["counterfactual"] and <div className="cm-cf">{"↺ " + str(m["counterfactual"])}</div>}
            {is_open and <div className="cm-criteria">
                {[
                    <div key={"cr-" + str(k)} className="cm-crit">
                        <span className={"cm-crit-icon cm-crit-" + str(crits[k]["status"])}>{("✓" if crits[k]["status"] == "met" else ("✗" if crits[k]["status"] == "unmet" else "?"))}</span>
                        <span className="cm-crit-label">{str(crits[k]["label"])}</span>
                        <span className="cm-crit-detail">{str(crits[k]["detail"])}</span>
                    </div>
                    for k in range(len(crits))
                ]}
                <div className="cm-crit-foot">{"Criteria confirmed: " + str(Math.round(Number(m["coverage"]) * 100)) + "% · score = hard gates × weighted soft criteria"}</div>
            </div>}
            <div className="cm-card-actions">
                {phone and <a className="cm-call" href={"tel:" + phone}>{"Call " + phone}</a>}
                {url and <a className="cm-link" href={url} target="_blank" rel="noreferrer">Website</a>}
                <button className="cm-why" onClick={lambda _e: MouseEvent { open_key = ("" if is_open else card_key); }}>{("Hide reasons" if is_open else "Why?")}</button>
            </div>
        </div>;
}

impl ChatPane.renderPlan(plan: Any) -> JsxElement {
    steps: list = list(plan["steps"]) if plan["steps"] else [];
    shared: list = list(plan["shared_documents"]) if plan["shared_documents"] else [];
    return
        <div className="cm-block">
            <div className="cm-block-title">
                <span>Your plan</span>
                <span className="cm-muted">{"ordered by value ÷ effort (Smith's rule) · ~" + str(plan["total_minutes"]) + " min of paperwork"}</span>
            </div>
            {[
                <div key={"st-" + str(i)} className="cm-step">
                    <div className="cm-step-num">{str(steps[i]["step_number"])}</div>
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <div className="cm-step-name">{str(steps[i]["agency_name"])}</div>
                        <div className="cm-step-act">{str(steps[i]["action_description"]) + " · " + str(steps[i]["deadline_label"]) + " · ~" + str(steps[i]["estimated_minutes"]) + " min"}</div>
                        {len(steps[i]["documents_needed"]) > 0 and <div className="cm-step-docs">{"Bring: " + ", ".join(list(steps[i]["documents_needed"]).slice(0, 3))}</div>}
                    </div>
                </div>
                for i in range(len(steps))
            ]}
            {len(shared) > 0 and <div className="cm-shared">{"Gather once: " + ", ".join([str(d[0]) + " (" + str(d[1]) + " steps)" for d in shared])}</div>}
        </div>;
}

impl ChatPane.renderRoute(route: Any, idx: int) -> JsxElement {
    hops: list = list(route["hops"]) if route["hops"] else [];
    return
        <div key={"route-" + str(idx)} className="cm-route">
            <div className="cm-route-head">
                <span>{"Route " + str(idx + 1) + " · " + str(route["hop_count"]) + " hop" + ("s" if route["hop_count"] != 1 else "")}</span>
                <span className="cm-muted">{"~" + str(route["total_days"]) + " days · success ≈ " + str(Math.round(Number(route["success_p"]) * 100)) + "% · cost " + str(route["cost"])}</span>
            </div>
            {[
                <div key={"hop-" + str(idx) + "-" + str(h)} className="cm-hop">
                    <div className="cm-hop-line">{str(hops[h]["from"]) + "  →  " + str(hops[h]["to"])}</div>
                    <div className="cm-hop-meta">{str(hops[h]["days"]) + " days · " + str(hops[h]["difficulty"]) + " · " + str(hops[h]["reason"])}</div>
                </div>
                for h in range(len(hops))
            ]}
        </div>;
}

impl ChatPane.renderWaterfall(trace: Any, narration: Any, idx: int) -> JsxElement {
    spans: list = list(trace["spans"]) if trace["spans"] else [];
    total = Number(trace["total_ms"]) if trace["total_ms"] else 1.0;
    if total <= 0 { total = 1.0; }
    return
        <div className="cm-waterfall">
            <div className="cm-wf-head">
                <span>{"Trace " + str(trace["trace_id"]).substring(0, 12) + "… · " + str(len(spans)) + " spans · OpenTelemetry GenAI shape"}</span>
                <button className="cm-why" onClick={lambda _e: MouseEvent { navigator.clipboard.writeText(JSON.stringify(trace, None, 2)); }}>Copy JSON</button>
            </div>
            {[
                <div key={"wf-" + str(k)} className="cm-wf-row">
                    <span className="cm-wf-name">{str(spans[k]["name"])}</span>
                    <div className="cm-wf-track">
                        <div
                            className={("cm-wf-bar cm-wf-llm" if str(spans[k]["kind"]) == "CLIENT" else "cm-wf-bar")}
                            style={{
                                "left": str(Number(spans[k]["start_ms"]) / total * 100) + "%",
                                "width": str(Math.max(0.8, Number(spans[k]["duration_ms"]) / total * 100)) + "%"
                            }}
                        />
                    </div>
                    <span className="cm-wf-ms">{fmtMs(spans[k]["duration_ms"])}</span>
                </div>
                for k in range(len(spans))
            ]}
            {narration and <div className="cm-wf-row">
                <span className="cm-wf-name">NarrateWalker · LLM (async)</span>
                <div className="cm-wf-track"><div className="cm-wf-bar cm-wf-llm cm-wf-async" style={{"left": "0%", "width": "100%"}}/></div>
                <span className="cm-wf-ms">{(fmtMs(narration["ms"]) if narration["ms"] else "…")}</span>
            </div>}
            <div className="cm-crit-foot">Engine spans are to scale; the narration runs after the answer is already on screen.</div>
        </div>;
}

impl ChatPane.renderResult(msg: dict, idx: int, is_last: bool) -> JsxElement {
    d: Any = msg["data"];
    tick = narr_tick;
    narr: Any = narrations[msg["id"]];
    lang = str(d["language"]) if d["language"] else "en";
    matches: list = list(d["matches"]) if d["matches"] else [];
    plan: Any = d["plan"] if d["plan"] else {};
    routes: list = list(d["routes"]) if d["routes"] else [];
    esc: Any = d["escalation"] if d["escalation"] else {};
    q: Any = d["question"] if d["question"] else {};
    trace: Any = d["trace"];
    prof: Any = d["profile"] if d["profile"] else {};
    chips: list = list(narr["chips"]) if (narr and narr["status"] == "ok" and narr["chips"]) else (list(d["chips"]) if d["chips"] else []);
    en_chips: list = list(d["chips"]) if d["chips"] else [];
    llm: Any = d["llm"] if d["llm"] else {};

    facts: list = [];
    if prof["category"] { facts = facts + [str(prof["category"]) + " · " + str(prof["urgency"]).replace("_", " ")]; }
    if Number(prof["income_annual"]) >= 0 { facts = facts + ["$" + Number(prof["income_annual"]).toLocaleString() + "/yr"]; }
    if Number(prof["household_size"]) > 0 { facts = facts + ["household " + str(prof["household_size"])]; }
    if Number(prof["age"]) > 0 { facts = facts + ["age " + str(prof["age"])]; }
    if prof["city"] or prof["state"] { facts = facts + [(str(prof["city"]) + ", " if prof["city"] else "") + str(prof["state"])]; }
    if prof["citizenship"] { facts = facts + [str(prof["citizenship"]).replace("_", " ")]; }

    return
        <div key={"m-" + str(idx)} className="cm-row msg-enter">
            <div className="cm-avatar">CM</div>
            <div className="cm-result">
                {(narr and narr["status"] == "ok") and <div className="cm-narration">
                    <span className="cm-spark">✦</span>
                    <span>{str(narr["message"])}</span>
                </div>}
                {(narr and narr["status"] == "pending") and <div className="cm-narration cm-narration-pending">✦ Writing a personalized summary…</div>}
                <div className="cm-bubble">{renderRich(str(d["reply"]))}</div>
                {len(facts) > 0 and <div className="cm-understood">
                    <span className="cm-muted">Understood</span>
                    {[<span key={"f" + str(i)} className="cm-fact">{facts[i]}</span> for i in range(len(facts))]}
                    {prof["carried_category"] and <span className="cm-fact cm-fact-dim">carried from earlier</span>}
                </div>}
                {esc["lead_line"] and <div className="cm-crisis">
                    <div className="cm-crisis-lead">{str(esc["lead_line"])}</div>
                    {[<div key={"cr" + str(i)} className="cm-crisis-item">{str(esc["crisis_resources"][i])}</div> for i in range(len(esc["crisis_resources"]) if esc["crisis_resources"] else 0)]}
                </div>}
                {len(matches) > 0 and <div className="cm-cards">
                    {[renderMatchCard(matches[j], idx, j) for j in range(len(matches) if len(matches) < 4 else 4)]}
                </div>}
                {(plan["steps"] and len(plan["steps"]) > 0) and renderPlan(plan)}
                {len(routes) > 0 and <div className="cm-block">
                    <div className="cm-block-title">
                        <span>Longer-term routes</span>
                        <span className="cm-muted">Yen k-shortest paths · cost = days + λ·difficulty − μ·ln P(yes)</span>
                    </div>
                    {[renderRoute(routes[r], r) for r in range(len(routes) if len(routes) < 2 else 2)]}
                </div>}
                {(is_last and q["text"]) and renderQuickReplies(q, lang)}
                {(is_last and len(chips) > 0) and <div className="cm-chips">
                    {[renderChip(str(chips[c]), str(en_chips[c]) if c < len(en_chips) else str(chips[c]), "") for c in range(len(chips))]}
                </div>}
                <div className="cm-hud">
                    <span className="cm-hud-fast">{"⚡ " + fmtMs(trace["total_ms"]) + " engine"}</span>
                    <span>{("1 LLM call (routing)" if llm["sync_used"] else "0 LLM calls on the critical path")}</span>
                    {Number(msg["rtt_ms"]) > 0 and <span>{"round trip " + fmtMs(msg["rtt_ms"])}</span>}
                    {(narr and narr["status"] == "ok") and <span className="cm-hud-llm">{"✦ narrated in " + fmtMs(narr["ms"]) + " · facts guard passed"}</span>}
                    {(narr and narr["status"] == "failed") and <span className="cm-muted">{"LLM narration unavailable — engine answer shown"}</span>}
                    <button className="cm-why" onClick={lambda _e: MouseEvent { waterfall_open = (-1 if waterfall_open == idx else idx); }}>{("Hide trace" if waterfall_open == idx else "Trace")}</button>
                </div>
                {waterfall_open == idx and renderWaterfall(trace, narr, idx)}
            </div>
        </div>;
}

impl ChatPane.renderMessage(msg: dict, idx: int, is_last: bool) -> JsxElement {
    role = str(msg["role"]);
    kind = str(msg["kind"]) if msg["kind"] else "text";
    if role == "user" {
        ev: list = list(msg["evidence"]) if msg["evidence"] else [];
        return
            <div key={"m-" + str(idx)} className="cm-row cm-row-user msg-enter">
                <div className="cm-user-bubble">{renderUserText(str(msg["text"]), ev)}</div>
            </div>;
    }
    if kind == "result" {
        return renderResult(msg, idx, is_last);
    }
    sugg: list = list(msg["suggestions"]) if msg["suggestions"] else [];
    return
        <div key={"m-" + str(idx)} className="cm-row msg-enter">
            <div className="cm-avatar">CM</div>
            <div className="cm-result">
                <div className={("cm-bubble cm-bubble-error" if kind == "error" else "cm-bubble")}>{renderRich(str(msg["text"]))}</div>
                {(is_last and len(sugg) > 0) and <div className="cm-chips cm-chips-col">
                    {[renderChip(str(sugg[s]), str(sugg[s]), "") for s in range(len(sugg))]}
                </div>}
            </div>
        </div>;
}

impl ChatPane.renderProfilePanel -> JsxElement {
    p: Any = profile_ctx if profile_ctx else {};
    has_case = bool(p["category"]);
    comp = Math.round(Number(p["completeness"]) * 100) if p["completeness"] else 0;
    rows = [
        ["Need", (str(p["category"]) + " · " + str(p["urgency"]).replace("_", " ")) if p["category"] else ""],
        ["Language", str(p["language"]).toUpperCase() if p["language"] else ""],
        ["Income", ("$" + Number(p["income_annual"]).toLocaleString() + "/yr") if (p["income_annual"] != None and Number(p["income_annual"]) >= 0) else ""],
        ["Household", str(p["household_size"]) if Number(p["household_size"]) > 0 else ""],
        ["Age", str(p["age"]) if Number(p["age"]) > 0 else ""],
        ["Location", ((str(p["city"]) + ", ") if p["city"] else "") + str(p["state"]) if p["state"] else ""],
        ["Status", str(p["citizenship"]).replace("_", " ") if p["citizenship"] else ""]
    ];
    return
        <div className="cm-panel cm-side-card">
            <div className="cm-side-title">Case file</div>
            {(not has_case) and <div className="cm-muted" style={{"fontSize": "12px"}}>Waiting for your first message…</div>}
            {has_case and <div>
                <div className="cm-meter-row"><span>Facts confirmed</span><span>{str(comp) + "%"}</span></div>
                <div className="cm-meter"><div style={{"width": str(comp) + "%", "background": "#FFE500"}}/></div>
                {[
                    <div key={"pr" + str(i)} className="cm-prow">
                        <span className="cm-muted">{rows[i][0]}</span>
                        <span className={("cm-pval" if rows[i][1] else "cm-pval cm-pval-empty")}>{rows[i][1] if rows[i][1] else "—"}</span>
                    </div>
                    for i in range(len(rows))
                ]}
                {pending_question and <div className="cm-next-q">{"Next question: " + pending_question.replace("_", " ") + " — chosen by value of information"}</div>}
            </div>}
        </div>;
}

impl ChatPane.renderPipeline -> JsxElement {
    agents = [
        ["IntakeWalker", "intake.parse", "Regex + lexicon parse, EN/ES, evidence spans"],
        ["LLM · understand", "chat understand_message", "Only when the parser can't route"],
        ["EligibilityWalker", "EligibilityWalker score", "40 programs · Beta posteriors · abstention"],
        ["NavigationWalker", "NavigationWalker plan", "Smith's-rule step ordering"],
        ["PathfinderWalker", "PathfinderWalker yen_k_shortest", "Yen k-shortest expected-cost routes"],
        ["EscalationWalker", "EscalationWalker crisis_route", "Crisis lines when risk is present"],
        ["CritiqueWalker", "reflexion.critique", "Reflexion write-back to the graph"]
    ];
    spans: list = list(last_trace["spans"]) if (last_trace and last_trace["spans"]) else [];
    return
        <div className="cm-panel cm-side-card" style={{"flex": "1"}}>
            <div className="cm-side-title">Agent pipeline · last turn</div>
            {[
                <div key={"ag" + str(i)} className="cm-agent">
                    <span className={("cm-agent-dot cm-agent-ran" if len([s for s in spans if s["name"] == agents[i][1]]) > 0 else "cm-agent-dot")}/>
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <div className="cm-agent-name">{agents[i][0]}</div>
                        <div className="cm-agent-role">{agents[i][2]}</div>
                    </div>
                    <span className="cm-agent-ms">{(fmtMs([s for s in spans if s["name"] == agents[i][1]][0]["duration_ms"]) if len([s for s in spans if s["name"] == agents[i][1]]) > 0 else "—")}</span>
                </div>
                for i in range(len(agents))
            ]}
            <div className="cm-agent">
                <span className="cm-agent-dot cm-agent-llm"/>
                <div style={{"flex": "1", "minWidth": "0"}}>
                    <div className="cm-agent-name">NarrateWalker · LLM</div>
                    <div className="cm-agent-role">The one LLM call — async, localizes the reply</div>
                </div>
                <span className="cm-agent-ms">async</span>
            </div>
        </div>;
}
