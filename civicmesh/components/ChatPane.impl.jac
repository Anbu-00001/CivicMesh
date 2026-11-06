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
        lambda err: Any -> dict {
            e = str(err);
            # The hosting proxy answers a failed request with its own HTML
            # error page; never show that to a person.
            if e.includes("<!DOCTYPE") or e.includes("<html") { e = "the hosting service returned an error page"; }
            return {"reports": [], "spawn_error": e};
        }
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

impl ChatPane.L(ui: Any, key: str, fallback: str) -> str {
    return str(ui[key]) if (ui and ui[key]) else fallback;
}

impl ChatPane.tierStyle(tier: str, ui: Any) -> dict {
    if tier == "likely" { return {"label": L(ui, "ui.likely", "Likely eligible"), "color": "#00E08A", "bg": "rgba(0,224,138,0.12)"}; }
    if tier == "possible" { return {"label": L(ui, "ui.possible", "Possible"), "color": "#5AA2FF", "bg": "rgba(90,162,255,0.12)"}; }
    if tier == "needs_info" { return {"label": L(ui, "ui.needs_info", "Needs info"), "color": "#FFB344", "bg": "rgba(255,179,68,0.12)"}; }
    return {"label": L(ui, "ui.unlikely", "Unlikely"), "color": "rgba(255,255,255,0.62)", "bg": "rgba(255,255,255,0.06)"};
}

impl ChatPane.resetCase -> None {
    profile_ctx = {};
    pending_question = "";
    # Nothing of the old case stays on screen: the words promise that, and the
    # phone may be handed to someone else next.
    setPageAttrs(pref_lang);
    messages = [{
        "role": "bot", "kind": "text", "id": "reset-" + str(Math.random()),
        "text": "New case started. Nothing from the earlier conversation is carried over. What's going on?",
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

impl ChatPane.sendMessage(text_override: str = "", answering: str = "", display: str = "", pin: bool = False) -> None {
    if is_loading { return; }
    effective = text_override if text_override else input_val;
    if not effective.strip() { return; }
    window.cm_saved_list = False;
    user_text = effective;
    input_val = "";
    ans = answering if answering else pending_question;
    # A tapped chip shows its (translated) label but sends the English
    # payload; the case language is pinned so the reply stays in it.
    case_lang = str(profile_ctx["language"]) if (profile_ctx and profile_ctx["language"]) else "";
    send_lang = pref_lang if pref_lang != "auto" else ((case_lang if (pin and case_lang) else "auto"));
    shown = display if display else user_text;
    user_msg = {"role": "user", "kind": "text", "id": "u" + str(Math.random()), "text": shown, "evidence": []};
    new_messages = messages + [user_msg];
    messages = new_messages;
    is_loading = True;

    # A request the hosting proxy never answers used to leave the typing dots
    # up forever, and `if is_loading { return; }` then ignored every new
    # message. After 30 s the turn is released with a retry; a late answer is
    # dropped. (CM_INFLIGHT is a plain object: React state read inside a
    # timer would be stale.)
    req_id = "r" + str(Math.random());
    CM_INFLIGHT["id"] = req_id;
    setTimeout(lambda {
        if CM_INFLIGHT["id"] == req_id {
            CM_INFLIGHT["id"] = "";
            messages = new_messages + [{"role": "bot", "kind": "error", "id": "t" + str(Math.random()), "text": L(footerUi(), "ui.busy", "No answer from the server after 30 seconds. The hosting service may be busy. Your message wasn't lost.") + " " + errorLines(), "retry": user_text, "retry_answering": ans, "retry_display": shown, "retry_pin": pin}];
            is_loading = False;
        }
    }, 30000);

    # The anonymous login can still be running when the first message goes
    # out (a suggestion tapped as the chat opens). A request without a token
    # gets a 401, and the client runtime then reloads the page and the
    # message is lost: wait for the login, and never send without one.
    uid = user_id;
    if auth_ready { uid = (await auth_ready) or user_id; }
    await ensureSignedIn();
    t0 = window.performance.now();
    res: Any = {"reports": [], "spawn_error": "couldn't sign in to the server"};
    if uid and jacIsLoggedIn() {
        res = await safeSpawn("IntakeWalker", {
            "conversation": user_text,
            "user_id": uid,
            "prior": profile_ctx if profile_ctx else {},
            "answering": ans,
            "preferred_language": send_lang
        });
    }
    # No account, or the server turned this turn away: the same answer through
    # the route that needs no account and keeps its own capacity (blind audit
    # F24). Nothing is stored on that route and no model is called.
    if res["spawn_error"] {
        res = await guestTurn({"conversation": user_text, "user_id": "guest", "prior": profile_ctx if profile_ctx else {}, "answering": ans, "preferred_language": send_lang});
    }
    rtt = window.performance.now() - t0;
    if CM_INFLIGHT["id"] != req_id { return; }
    CM_INFLIGHT["id"] = "";

    reps = res["reports"];
    n = len(reps) if reps else 0;
    data: Any = reps[n - 1] if n > 0 else None;
    if res["spawn_error"] or (not data) or (not data["trace"]) {
        new_messages = new_messages + [{"role": "bot", "kind": "error", "id": "e" + str(Math.random()), "text": L(footerUi(), "ui.busy", "I couldn't reach the server just now. Your message wasn't lost, so you can try again.") + " " + errorLines(), "retry": user_text, "retry_answering": ans, "retry_display": shown, "retry_pin": pin}];
        messages = new_messages;
        is_loading = False;
        return;
    }

    # A crisis or concern turn switches on a private session by itself.
    if data["privacy"] and data["privacy"]["private_turn"] and not private_on { setPrivate(True); }
    user_msg["evidence"] = (data["evidence"] if data["evidence"] else []) if shown == user_text else [];
    bot_id = "b" + str(Math.random());
    new_messages = new_messages + [{"role": "bot", "kind": "result", "id": bot_id, "data": data, "rtt_ms": rtt}];
    messages = new_messages;
    profile_ctx = data["profile"];
    ln = data["language_name"];
    lang_label = (str(ln[1]) + (" · " + str(ln[0]) if str(ln[0]) != str(ln[1]) else "")) if (ln and data["narrate_language"] != "auto") else "not identified";
    if pref_lang == "auto" and data["reply_language"] { setPageAttrs(str(data["reply_language"])); }
    q = data["question"];
    pending_question = str(q["key"]) if (q and q["key"]) else "";
    last_trace = data["trace"];
    last_llm = data["llm"] if data["llm"] else {};
    on_walker_event(spansToEvents(list(data["trace"]["spans"])));
    is_loading = False;

    llm = data["llm"];
    if llm and llm["narrate"] {
        narrate(bot_id, data, user_text);
    }
    li = data["language_info"];
    code = str(li["code"]) if li else "";
    # A language with a message catalog gets its answer, question, chips and
    # labels composed natively by the server: nothing to translate. Others get
    # the short strings (fast) and the full answer (slower) translated after.
    # Translation and the local search need an account: the no-account route has neither.
    if data["guest"] { return; }
    if code and code != "en" and code != "es" and li["tier"] != "interpreter" and str(data["reply_language"]) != code {
        localizeStrings(bot_id, data);
        localize(bot_id, data);
    }
    prof = data["profile"];
    cat = str(prof["category"]) if prof else "";
    if prof and prof["state"] and (cat == "housing" or cat == "healthcare" or cat == "legal") {
        findLocal(bot_id, data);
    }
}

impl ChatPane.findLocal(msg_id: str, data: Any) -> None {
    prof = data["profile"];
    flags: list = list(prof["flags"]) if prof["flags"] else [];
    locals[msg_id] = {"status": "pending"};
    narr_tick = Math.random();
    res = await safeSpawn("LocalHelpWalker", {
        "category": str(prof["category"]), "city": str(prof["city"]) if prof["city"] else "",
        "state": str(prof["state"]), "homeless": flags.includes("homeless")
    });
    reps = res["reports"];
    r = reps[len(reps) - 1] if (reps and len(reps) > 0) else None;
    locals[msg_id] = {"status": ("ok" if (r and r["offices"] and len(r["offices"]) > 0) else "none"), "data": r};
    narr_tick = Math.random();
}

impl ChatPane.localize(msg_id: str, data: Any) -> None {
    localized[msg_id] = {"status": "pending"};
    narr_tick = Math.random();
    loc = data["loc"] if data["loc"] else {};
    res = await safeSpawn("LocalizeWalker", {"text": str(data["reply"]), "language": str(data["language_info"]["code"]), "strings": [], "text_token": (str(loc["text_token"]) if loc["text_token"] else "")});
    reps = res["reports"];
    r = reps[len(reps) - 1] if (reps and len(reps) > 0) else None;
    localized[msg_id] = {"status": ("ok" if (r and r["ok"]) else "failed"), "data": r};
    narr_tick = Math.random();
}

impl ChatPane.localizeStrings(msg_id: str, data: Any) -> None {
    q = data["question"];
    q_text = str(q["text"]) if (q and q["text"]) else "";
    quick: list = list(q["options"]) if (q and q["options"]) else [];
    chips_en: list = list(data["chips"]) if data["chips"] else [];
    affects_en = str(q["affects_label"]) if (q and q["affects_label"]) else "";
    # The server's own list (same order: question, what it affects, quick
    # replies, chips): the token covers exactly these strings.
    loc = data["loc"] if data["loc"] else {};
    strings: list = list(loc["strings"]) if loc["strings"] else [];
    strings_token = str(loc["strings_token"]) if loc["strings_token"] else "";
    res = await safeSpawn("LocalizeWalker", {"text": "", "language": str(data["language_info"]["code"]), "strings": strings, "strings_token": strings_token});
    reps = res["reports"];
    r = reps[len(reps) - 1] if (reps and len(reps) > 0) else None;
    ls: list = list(r["strings"]) if (r and r["strings"]) else [];
    ok = len(ls) == len(strings) and r["strings_translated"] > 0;
    n_quick = len(quick);
    localized[msg_id + ":s"] = {
        "q_text": (str(ls[0]) if ok else ""),
        "affects": (str(ls[1]) if (ok and affects_en) else ""),
        "quick": (ls.slice(2, 2 + n_quick) if ok else []),
        "chips": (ls.slice(2 + n_quick) if ok else [])
    };
    narr_tick = Math.random();
}

impl ChatPane.renderInterpreter(card: Any, open_default: bool) -> JsxElement {
    if not card or not card["en"] { return <div/>; }
    return
        <details className="cm-interp" open={open_default}>
            <summary>{"🗣 Interpreter card · " + str(card["language"]) + (" · " + str(card["endonym"]) if str(card["endonym"]) != str(card["language"]) else "")}</summary>
            <div className="cm-interp-body">
                <div className="cm-interp-show">Show this at any benefits office, clinic or court:</div>
                <div className="cm-interp-line">{str(card["en"])}</div>
                <div className="cm-interp-line cm-interp-es">{str(card["es"])}</div>
                <div className="cm-muted cm-interp-tip">{str(card["tip"])}</div>
                <div className="cm-crit-src">{str(card["basis"])}</div>
            </div>
        </details>;
}

impl ChatPane.renderLangPicker -> JsxElement {
    langs: list = list(platform["languages"]) if (platform and platform["languages"]) else lang_fallback;
    # Unmarked: the whole answer is composed in that language (message
    # catalog). Others are translated after the answer arrives.
    tier_mark: dict = {"instant": " · translated", "translate": " · translated", "llm": " · AI-translated", "interpreter": " · interpreter card"};
    return
        <select
            className="cm-lang-select"
            value={pref_lang}
            title="Reply language — auto-detect, or pick yours"
            aria-label="Reply language"
            onChange={lambda e: ChangeEvent {
                pref_lang = e.target.value;
                try { localStorage.setItem("cm_lang", e.target.value); } except Exception as _ex {}
                applyPageLang(e.target.value);
            }}
        >
            <option value="auto">🌐 Auto-detect language</option>
            {[<option key={str(l["code"])} value={str(l["code"])}>{str(l["endonym"]) + (" — " + str(l["name"]) if str(l["endonym"]) != str(l["name"]) else "") + ("" if l["catalog"] else str(tier_mark[str(l["tier"])]))}</option> for l in langs]}
        </select>;
}

impl ChatPane.renderLocal(loc: Any) -> JsxElement {
    if not loc { return <div/>; }
    if loc["status"] == "pending" {
        return <div className="cm-block cm-local cm-muted">Looking up offices near you in HUD and HRSA open data…</div>;
    }
    if loc["status"] != "ok" { return <div/>; }
    d = loc["data"];
    offices: list = list(d["offices"]);
    return
        <div className="cm-block cm-local">
            <div className="cm-block-title">
                <span>{"Near you · " + str(d["place"])}</span>
                <span className="cm-muted">{"federal open data · " + (("cached" if d["cached"] else str(Math.round(Number(d["latency_ms"]))) + " ms"))}</span>
            </div>
            {[
                <div key={"lo" + str(i)} className="cm-local-row">
                    <div className="cm-local-main">
                        <div className="cm-local-name">{str(offices[i]["name"])}</div>
                        <div className="cm-muted cm-local-meta">{str(offices[i]["kind"]) + " · " + str(offices[i]["detail"])}</div>
                        <div className="cm-muted cm-local-meta">{str(offices[i]["address"])}</div>
                    </div>
                    <div className="cm-local-actions">
                        {offices[i]["phone"] and <a className="cm-call" href={"tel:" + str(offices[i]["phone"])}><bdi dir="ltr">{str(offices[i]["phone"])}</bdi></a>}
                        {offices[i]["email"] and <a className="cm-link" href={"mailto:" + str(offices[i]["email"])}>Email</a>}
                        {offices[i]["url"] and <a className="cm-link" href={(str(offices[i]["url"]) if str(offices[i]["url"]).startsWith("http") else "https://" + str(offices[i]["url"]))} target="_blank" rel="noreferrer">Website</a>}
                    </div>
                </div>
                for i in range(len(offices))
            ]}
            <div className="cm-crit-foot">{"Source: " + str(offices[0]["source"]) + ". Listings come straight from the federal datasets; call ahead to confirm hours."}</div>
        </div>;
}

impl ChatPane.narrate(msg_id: str, data: Any, user_text: str) -> None {
    narrations[msg_id] = {"status": "pending"};
    narr_tick = Math.random();
    t0 = window.performance.now();
    res = await safeSpawn("NarrateWalker", {
        "user_message": user_text,
        "language": data["narrate_language"] if data["narrate_language"] else data["language"],
        "facts": data["facts"],
        # Only server-issued, visitor-bound tokens get narrated (no free LLM relay).
        "narrate_token": data["narrate_token"] if data["narrate_token"] else "",
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
            onClick={lambda _e: MouseEvent { sendMessage(payload, answering, label, True); }}
            disabled={is_loading}
        >
            {label}
        </button>;
}

impl ChatPane.quickOptions(key: str, es: bool) -> list {
    opts: list = [];
    if YES_NO_KEYS.includes(key) {
        opts = [["Sí" if es else "Yes", "sí" if es else "yes"], ["No", "no"]];
    } elif key == "need" {
        if es {
            opts = [["Comida", "necesito comida"], ["Vivienda", "necesito ayuda con vivienda"], ["Salud", "necesito un médico"], ["Ayuda legal", "necesito un abogado"]];
        } else {
            opts = [["Food", "I need food"], ["Housing", "I need help with housing"], ["Health care", "I need a doctor"], ["Legal help", "I need a lawyer"]];
        }
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
            opts = [["Ciudadano/a", "soy ciudadano"], ["Residente permanente", "soy residente permanente"], ["Refugiado/a o asilado/a", "soy refugiado"], ["Sin papeles", "estoy sin papeles"]];
        } else {
            opts = [["U.S. citizen", "I'm a US citizen"], ["Green card", "I have a green card"], ["Refugee / asylee", "I'm a refugee"], ["No status", "I'm undocumented"]];
        }
    }
    return opts;
}

impl ChatPane.renderQuickReplies(q: Any, lang: str, labels: list, q_text: str, affects_text: str) -> JsxElement {
    key = str(q["key"]);
    es = lang == "es";
    # Server options: [label in the reply language, English payload].
    opts: list = list(q["options"]) if (q["options"] and len(q["options"]) > 0) else quickOptions(key, es);
    # Localized labels (same order) when the translator has returned them;
    # the payload stays English so the engine reads it, with the case
    # language pinned so it isn't mistaken for a language switch.
    has_local = labels and len(labels) == len(opts);
    return
        <div className="cm-question">
            <div className="cm-question-text">
                <span className="cm-q-mark">?</span>
                <span dir="auto">{q_text if q_text else str(q["text"])}</span>
                {Number(q["affects"]) > 0 and <span className="cm-q-gain">{affects_text if affects_text else (str(q["affects_label"]) if q["affects_label"] else (("afecta " if es else "affects ") + str(q["affects"]) + (" programas" if es else " matches")))}</span>}
            </div>
            {len(opts) > 0 and <div className="cm-chips">
                {[renderChip((str(labels[i]) if has_local else str(opts[i][0])), str(opts[i][1]), key) for i in range(len(opts))]}
            </div>}
        </div>;
}

impl ChatPane.renderCrisisPin -> Any {
    for i in range(len(messages) - 1, -1, -1) {
        d: Any = messages[i]["data"] if messages[i]["kind"] == "result" else None;
        esc: Any = d["escalation"] if d else None;
        if esc and esc["lead_phone"] {
            phone = str(esc["lead_phone"]);
            return
                <div className="cm-crisis-pin" role="note">
                    <a className="cm-crisis-pin-call" href={"tel:" + phone}>{L(footerUi(), "ui.call", "Call") + " "}<bdi dir="ltr">{phone}</bdi></a>
                </div>;
        }
    }
    return None;
}

impl ChatPane.ensureSignedIn -> None {
    # After a restart the old token is refused, and the client runtime answers
    # a refused walker call by reloading the page: the thread and the message
    # are gone, with no number on screen (blind audit, 2026-11). So check first
    # and sign in again quietly. The case itself is held by the client.
    now = Date.now();
    if now - Number(CM_AUTH["checked"]) < 20000 { return; }
    CM_AUTH["checked"] = now;
    token = localStorage.getItem("jac_token");
    if not token { return; }
    probe = await fetch("/user/me", {"headers": {"Authorization": "Bearer " + str(token)}}).catch(lambda e: Any -> dict { return {"status": 0}; });
    if probe.status != 401 and probe.status != 403 { return; }
    localStorage.removeItem("jac_token");
    priv = False;
    try { priv = sessionStorage.getItem("cm_private") == "1"; } except Exception as _ex {}
    store = sessionStorage if priv else localStorage;
    uid = store.getItem("cm_uid");
    pw = store.getItem("cm_pw");
    if uid and pw {
        await jacSignup(uid, pw).catch(lambda e: Any -> dict { return {}; });
        await jacLogin(uid, pw).catch(lambda e: Any -> dict { return {}; });
    }
}

impl ChatPane.renderMatchCard(m: Any, idx: int, j: int, ui: Any) -> JsxElement {
    if m["pinned"] {
        line_phone = str(m["contact_phone"]) if m["contact_phone"] else "";
        return
            <div key={"card-" + str(idx) + ":" + str(j)} className="cm-card cm-card-line card-enter">
                <div className="cm-card-name" lang="en" dir="auto">{str(m["resource_name"])}</div>
                <div className="cm-card-actions">
                    {line_phone and <a className="cm-call" href={"tel:" + line_phone}>{L(ui, "ui.call", "Call") + " "}<bdi dir="ltr">{line_phone}</bdi></a>}
                    {m["online_url"] and <a className="cm-link" href={str(m["online_url"])} target="_blank" rel="noreferrer">{L(ui, "ui.website", "Website")}</a>}
                </div>
            </div>;
    }
    ts = tierStyle(str(m["tier"]), ui);
    cat_key = {"food": "opt.food", "housing": "opt.housing", "healthcare": "opt.health", "legal": "opt.legal", "money": "opt.money"}[str(m["category"])];
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
    ben: Any = m["benefit"] if m["benefit"] else {};
    # A policy change that affects this person (e.g. the Oct 1, 2026 Medicaid
    # rule for refugees) is surfaced on the card, not hidden under "Why?".
    notes: list = [str(c["note"]) for c in crits if c["note"] and c["key"] == "citizenship"];
    # A 24/7 line has no application to approve: odds there only confuse
    # someone in crisis (outside judge, 2026-10-28).
    nm_low = str(m["resource_name"]).toLowerCase();
    is_line = nm_low.includes("hotline") or nm_low.includes("lifeline") or nm_low.includes("helpline") or nm_low.includes("safeline");
    return
        <div key={"card-" + card_key} className="cm-card card-enter">
            <div className="cm-card-top">
                <span className="cm-tier" style={{"color": ts["color"], "background": ts["bg"]}}>{ts["label"]}</span>
                <span className="cm-cap">{(L(ui, "ui.open_now", "Open now") if cap == "open" else (L(ui, "ui.waitlist", "Waitlist") if cap == "waitlist" else cap)) + " · " + (L(ui, cat_key, str(m["category"])) if cat_key else str(m["category"]))}</span>
            </div>
            <div className="cm-card-name" lang="en" dir="auto">{str(m["resource_name"])}</div>
            <div className="cm-meter-row">
                <span>{L(ui, "ui.eligibility", "Eligibility")}</span>
                <span style={{"color": ts["color"]}}>{str(pct) + "%"}</span>
            </div>
            <div className="cm-meter"><div style={{"width": str(pct) + "%", "background": ts["color"]}}/></div>
            {ben["label"] and <div className="cm-benefit" title={str(ben["basis"])}>
                <span className="cm-benefit-amt">{str(ben["label"])}</span>
                <span className="cm-muted">{L(ui, "ui.est_benefit", "estimated benefit") + " · " + L(ui, "ui.fact_household", "household of {n}").replace("{n}", str(ben["household"])) + (" (" + L(ui, "ui.assumed", "assumed") + ")" if ben["assumed_household"] else "")}</span>
            </div>}
            {len(notes) > 0 and <div className="cm-policy-note" lang="en" dir="auto">{"⚑ " + notes[0]}</div>}
            {m["counterfactual"] and <div className="cm-cf" lang="en" dir="auto">{"↺ " + str(m["counterfactual"])}</div>}
            {is_open and <div className="cm-criteria">
                {[
                    <div key={"cr-" + str(k)} className="cm-crit">
                        <span className={"cm-crit-icon cm-crit-" + str(crits[k]["status"])}>{("✓" if crits[k]["status"] == "met" else ("✗" if crits[k]["status"] == "unmet" else "?"))}</span>
                        <span className="cm-crit-label">{str(crits[k]["label"])}</span>
                        <span className="cm-crit-detail">
                            {str(crits[k]["detail"])}
                            {crits[k]["note"] and <span className="cm-crit-note">{" — " + str(crits[k]["note"])}</span>}
                            {crits[k]["source"] and <span className="cm-crit-src">{str(crits[k]["source"]) + (" · typical, varies locally" if crits[k]["typical"] else "")}</span>}
                        </span>
                    </div>
                    for k in range(len(crits))
                ]}
                {ben["basis"] and <div className="cm-crit-foot">{"Benefit estimate: " + str(ben["basis"])}</div>}
                <div className="cm-crit-foot">{"Checked: " + str(Math.round(Number(m["coverage"]) * 100)) + "% of what this program asks · rules as of Sep 27, 2026"}</div>
            </div>}
            <div className="cm-card-actions">
                {phone and <a className="cm-call" href={"tel:" + phone}>{L(ui, "ui.call", "Call") + " "}<bdi dir="ltr">{phone}</bdi></a>}
                {url and <a className="cm-link" href={url} target="_blank" rel="noreferrer">{L(ui, "ui.website", "Website")}</a>}
                <button className="cm-why" onClick={lambda _e: MouseEvent { open_key = ("" if is_open else card_key); }}>{(L(ui, "ui.hide", "Hide reasons") if is_open else L(ui, "ui.why", "Why?"))}</button>
            </div>
        </div>;
}

impl ChatPane.renderPlan(plan: Any, ui: Any) -> JsxElement {
    steps: list = list(plan["steps"]) if plan["steps"] else [];
    shared: list = list(plan["shared_documents"]) if plan["shared_documents"] else [];
    return
        <div className="cm-block">
            <div className="cm-block-title">
                <span>{L(ui, "ui.plan", "Your plan")}</span>
                <span className="cm-muted">{L(ui, "ui.plan_sub", "most useful and quickest first · about {n} min of paperwork").replace("{n}", str(plan["total_minutes"]))}</span>
            </div>
            {[
                <div key={"st-" + str(i)} className="cm-step">
                    <div className="cm-step-num">{str(steps[i]["step_number"])}</div>
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <div className="cm-step-name">{str(steps[i]["agency_name"])}</div>
                        <div className="cm-step-act">{str(steps[i]["action_description"]) + " · " + str(steps[i]["deadline_label"]) + " · ~" + str(steps[i]["estimated_minutes"]) + " min"}</div>
                        {len(steps[i]["documents_needed"]) > 0 and <div className="cm-step-docs">{L(ui, "ui.bring", "Bring") + ": " + ", ".join(list(steps[i]["documents_needed"]).slice(0, 3))}</div>}
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
    lname: list = list(d["language_name"]) if d["language_name"] else ["English", "English"];
    # With a message catalog the server composed the answer in the user's
    # language (native). Without one the engine text is English, so the
    # narration IS the answer until the full translation arrives.
    reply_lang = str(d["reply_language"]) if d["reply_language"] else "en";
    foreign = lang != "en" and lang != "es" and reply_lang != lang;
    native_chips = lang != "en" and reply_lang == lang;
    ui: Any = d["ui"] if d["ui"] else {};
    loc_t: Any = localized[msg["id"]];
    linfo: Any = d["language_info"] if d["language_info"] else {};
    interp_tier = linfo["tier"] == "interpreter";
    card: Any = d["interpreter"] if d["interpreter"] else {};
    matches: list = list(d["matches"]) if d["matches"] else [];
    # After "I want to kill myself" the answer is the crisis line, not a list of
    # documents to bring (blind audit, 2026-11). Everything else is one tap away.
    held_back = bool(d["escalation"] and d["escalation"]["danger"]) and not open_programs.includes(str(msg["id"]));
    shown_matches: list = [m for m in matches if m["pinned"]] if held_back else matches;
    n_held = len(matches) - len(shown_matches);
    plan: Any = d["plan"] if d["plan"] else {};
    routes: list = list(d["routes"]) if d["routes"] else [];
    esc: Any = d["escalation"] if d["escalation"] else {};
    # Blind audit, 2026-11: near misses were computed and never shown, so every "no" was silent.
    card_names: list = [m["resource_name"] for m in shown_matches[:4]];
    near_all: list = list(d["near_misses"]) if d["near_misses"] else [];
    near_show: list = [] if held_back else [n for n in near_all if not card_names.includes(n["resource_name"])];
    pflags: list = list(d["profile"]["flags"]) if (d["profile"] and d["profile"]["flags"]) else [];
    pstatus: str = str(d["profile"]["citizenship"]) if (d["profile"] and d["profile"]["citizenship"]) else "";
    charge_asked: bool = pflags.includes("public_charge_q");
    charge_show: bool = (not held_back) and (charge_asked or ["eligible_immigrant", "humanitarian", "non_citizen", "cuban_haitian_entrant", "cofa"].includes(pstatus));
    charge_block: Any = <details className="cm-block cm-charge" open={charge_asked} dir="auto">
        <summary className="cm-block-title">{L(ui, "ui.charge_title", "Benefits and your immigration case")}</summary>
        <p>{L(ui, "ui.charge_body", "Since September 18, 2026, officers can weigh means-tested benefits you use yourself when you apply for a green card. Benefits your family members use generally aren't counted, and refugees and asylees are exempt. Talk to an accredited immigration representative before you decide.")}</p>
        <a href="https://www.immigrationadvocates.org/nonprofit/legaldirectory/" target="_blank" rel="noopener noreferrer">{L(ui, "ui.charge_link", "Find free immigration legal help")}</a>
    </details>;
    q: Any = d["question"] if d["question"] else {};
    # A machine-drafted catalog (no native review yet): say so in the user's
    # language, keep the English original one tap away, and show the English
    # of any crisis line under it (HHS §1557 guidance on unreviewed MT).
    mt_draft = native_chips and str(linfo["catalog_review"]) == "draft" and bool(d["reply_en"]);
    report_url = "https://github.com/Anbu-00001/CivicMesh/issues/new?template=translation.yml&labels=translation&title=" + encodeURIComponent("[" + lang + "] translation: ");
    trace: Any = d["trace"];
    prof: Any = d["profile"] if d["profile"] else {};
    loc_c: Any = localized[msg["id"] + ":s"];
    en_chips: list = list(d["chips"]) if d["chips"] else [];
    chip_labels: list = list(d["chip_labels"]) if (d["chip_labels"] and len(d["chip_labels"]) == len(en_chips)) else [];
    chips: list = chip_labels if (native_chips and len(chip_labels) > 0) else (list(loc_c["chips"]) if (loc_c and loc_c["chips"] and len(loc_c["chips"]) > 0) else (list(narr["chips"]) if (narr and narr["status"] == "ok" and narr["chips"] and len(narr["chips"]) == len(en_chips)) else en_chips));
    llm: Any = d["llm"] if d["llm"] else {};

    # Small talk understood nothing new: no "Understood" row under "hi".
    facts: list = [];
    if not prof["small_talk"] {
        cat_keys: dict = {"food": ("opt.food", "Food"), "housing": ("opt.housing", "Housing"), "healthcare": ("opt.health", "Health care"), "legal": ("opt.legal", "Legal help"), "money": ("opt.money", "Money & child care")};
        cat_name: Any = lambda c: Any { pair: Any = cat_keys[str(c)]; return L(ui, pair[0], pair[1]) if pair else str(c).replace("_", " "); };
        if prof["category"] { facts = facts + [cat_name(prof["category"]) + (" · " + L(ui, "ui.fact_urgent", "urgent") if str(prof["urgency"]) == "immediate" else "")]; }
        if prof["secondary"] and len(prof["secondary"]) > 0 { facts = facts + [str(cat_name(c)) for c in list(prof["secondary"])]; }
        if Number(prof["income_annual"]) >= 0 { facts = facts + ["$" + Number(prof["income_annual"]).toLocaleString() + " " + L(ui, "ui.fact_year", "a year")]; }
        if Number(prof["household_size"]) > 0 { facts = facts + [L(ui, "ui.fact_household", "household of {n}").replace("{n}", str(prof["household_size"]))]; }
        if Number(prof["age"]) > 0 { facts = facts + [L(ui, "ui.fact_age", "age {n}").replace("{n}", str(prof["age"]))]; }
        if prof["city"] or prof["state"] { facts = facts + [(str(prof["city"]) + ", " if prof["city"] else "") + str(prof["state"])]; }
        cz_keys: dict = {"citizen": ("opt.citizen", "U.S. citizen"), "eligible_immigrant": ("opt.green_card", "Green card"), "humanitarian": ("opt.refugee", "Refugee / asylee"), "undocumented": ("opt.no_status", "No status"), "non_citizen": ("opt.no_status", "No status")};
        cz: Any = cz_keys[str(prof["citizenship"])] if prof["citizenship"] else None;
        if prof["citizenship"] { facts = facts + [L(ui, cz[0], cz[1]) if cz else str(prof["citizenship"]).replace("_", " ")]; }
    }

    # The model's summary can be wrong, so it never comes before the engine's
    # answer (blind audit F25). In a language with no catalog it is the only
    # text the person can read; it still follows the crisis box.
    summary_block: Any = None;
    if narr and narr["status"] == "ok" {
        summary_block = <div className={"cm-narration" + (" cm-narration-main" if foreign else "")} lang={lang} dir="auto">
            <span className="cm-spark" aria-hidden="true">✦</span>
            <span>
                {foreign and <span className="cm-lang-tag">{str(lname[1])}</span>}
                <span className="cm-narration-label">{L(ui, "ui.ai_summary", "AI summary. It can be wrong. The program list is what counts.")}</span>
                {str(narr["message"])}
            </span>
        </div>;
    } elif narr and narr["status"] == "pending" {
        summary_block = <div className="cm-narration cm-narration-pending">{("✦ Writing this in " + str(lname[1]) + "…") if foreign else "✦ Writing a personalized summary…"}</div>;
    }
    can_save: bool = (not held_back) and (not private_on) and len(shown_matches) > 0;

    return
        <div key={"m-" + str(idx)} className="cm-row msg-enter">
            <div className="cm-avatar">CM</div>
            <div className="cm-result">
                {esc["lead_line"] and <div className="cm-crisis">
                    <div className="cm-crisis-lead">{str(esc["lead_line"])}</div>
                    {esc["lead_line_en"] and <div className="cm-crisis-en" lang="en" dir="ltr">{"In English: " + str(esc["lead_line_en"])}</div>}
                    {[<div key={"cr" + str(i)} className="cm-crisis-item">{str(esc["crisis_resources"][i])}</div> for i in range(len(esc["crisis_resources"]) if esc["crisis_resources"] else 0)]}
                </div>}
                {foreign and summary_block}
                {(foreign and narr and narr["status"] == "failed") and <div className="cm-narration cm-narration-pending">{"Couldn't reach the translator just now — here is the answer in English."}</div>}
                {interp_tier and renderInterpreter(card, True)}
                {(loc_t and loc_t["status"] == "ok") and <div className="cm-bubble cm-bubble-translated" lang={lang}>
                    <div className="cm-muted cm-bubble-label">{str(lname[1]) + " · full answer, translated by " + (("NVIDIA Riva Translate" if str(loc_t["data"]["model"]).includes("riva") else ("Gemma 4" if str(loc_t["data"]["model"]).includes("gemma") else "an LLM"))) + " · numbers checked"}</div>
                    <div style={{"whiteSpace": "pre-wrap"}}>{str(loc_t["data"]["text"])}</div>
                </div>}
                {(loc_t and loc_t["status"] == "pending") and <div className="cm-narration cm-narration-pending">{"Translating the full answer into " + str(lname[1]) + "…"}</div>}
                {(loc_t and loc_t["status"] == "failed") and <div className="cm-narration cm-narration-pending">
                    <span>{"The full translation into " + str(lname[1]) + " didn't arrive in time — the answer below is in English. "}</span>
                    <button className="cm-why" onClick={lambda _e: MouseEvent { localize(msg["id"], d); }}>Try again</button>
                </div>}
                <div className={"cm-bubble" + (" cm-bubble-en" if foreign else "")} lang={reply_lang} dir="auto">
                    {foreign and <div className="cm-muted cm-bubble-label">Engine answer · English</div>}
                    {interp_tier and <div className="cm-muted cm-bubble-label">{"Answer in " + ("Spanish" if lang == "es" else "English") + " — text translation for " + str(linfo["name"]) + " isn't reliable yet"}</div>}
                    {renderRich(str(d["reply"]))}
                    {mt_draft and <div className="cm-mt-note">
                        <span>{L(ui, "ui.mt_draft", "Machine translation, not yet checked by a native speaker — it may contain mistakes. Names, amounts and phone numbers are exact.")}</span>
                        <span className="cm-mt-actions">
                            <button className="cm-why" onClick={lambda _e: MouseEvent { en_open = ("" if en_open == msg["id"] else msg["id"]); }} aria-expanded={("true" if en_open == msg["id"] else "false")}>{L(ui, "ui.show_en", "Show the English original")}</button>
                            <a className="cm-link" href={report_url} target="_blank" rel="noreferrer">{L(ui, "ui.report", "Report a translation mistake")}</a>
                        </span>
                    </div>}
                    {(mt_draft and en_open == msg["id"]) and <div className="cm-en-original" lang="en" dir="ltr">
                        <div className="cm-muted cm-bubble-label">English original · same engine answer</div>
                        {renderRich(str(d["reply_en"]))}
                    </div>}
                </div>
                {((not interp_tier) and foreign) and renderInterpreter(card, False)}
                {len(facts) > 0 and <div className="cm-understood">
                    <span className="cm-muted">{L(ui, "ui.understood", "Understood")}</span>
                    {[<span key={"f" + str(i)} className="cm-fact">{facts[i]}</span> for i in range(len(facts))]}
                    {prof["carried_category"] and <span className="cm-fact cm-fact-dim">{L(ui, "ui.carried", "from earlier")}</span>}
                </div>}
                {(d["privacy"] and d["privacy"]["private_turn"] and is_last) and <div className="cm-private-note">{L(ui, "ui.private_note", "Private session is on: once you close this tab, this browser keeps nothing about this conversation. Quick exit leaves instantly.")}</div>}
                {(charge_show and charge_asked) and charge_block}
                {len(shown_matches) > 0 and <div className="cm-cards">
                    {[renderMatchCard(shown_matches[j], idx, j, ui) for j in range(len(shown_matches) if len(shown_matches) < 4 else 4)]}
                </div>}
                {len(near_show) > 0 and <div className="cm-block cm-near" dir="auto">
                    <div className="cm-block-title"><span>{L(ui, "ui.near_title", "Not on this list, and why")}</span></div>
                    {[<p key={"nm" + str(i)}><strong>{near_show[i]["resource_name"]}</strong>{": " + str(near_show[i]["counterfactual"])}</p> for i in range(len(near_show))]}
                    <p className="cm-muted">{L(ui, "ui.near_ask", "You can still apply. Only the program's office can say no.")}</p>
                </div>}
                {(charge_show and not charge_asked) and charge_block}
                {(not foreign) and summary_block}
                {can_save and <div className="cm-save" dir="auto">
                    <button className="cm-why" onClick={lambda _e: MouseEvent { saveList(msg["id"], shown_matches, plan, ui); }}>{("✓ " if saved_list == msg["id"] else "") + L(ui, "ui.save_list", "Save this list")}</button>
                    <span className="cm-muted">{L(ui, "ui.save_note", "This page forgets the list when you reload or close it.")}</span>
                </div>}
                {(held_back and n_held > 0) and <button className="cm-why cm-show-programs" onClick={lambda _e: MouseEvent { open_programs = open_programs + [str(msg["id"])]; }}>{L(ui, "ui.show_programs", "Show programs and next steps") + " (" + str(n_held) + ")"}</button>}
                {((not held_back) and plan["steps"] and len(plan["steps"]) > 0) and renderPlan(plan, ui)}
                {(not held_back) and renderLocal(locals[msg["id"]])}
                {(len(routes) > 0 and waterfall_open == idx) and <div className="cm-block">
                    <div className="cm-block-title">
                        <span>{L(ui, "ui.routes", "Longer-term routes")}</span>
                        <span className="cm-muted">Yen k-shortest paths · cost = days + λ·difficulty − μ·ln P(yes)</span>
                    </div>
                    {[renderRoute(routes[r], r) for r in range(len(routes) if len(routes) < 2 else 2)]}
                </div>}
                {(is_last and q["text"] and not held_back) and renderQuickReplies(q, lang, (list(loc_c["quick"]) if (loc_c and loc_c["quick"]) else []), (str(loc_c["q_text"]) if (loc_c and loc_c["q_text"]) else ""), (str(loc_c["affects"]) if (loc_c and loc_c["affects"]) else ""))}
                {(is_last and len(chips) > 0 and not held_back) and <div className="cm-chips" dir="auto">
                    {[renderChip(str(chips[c]), str(en_chips[c]) if c < len(en_chips) else str(chips[c]), "") for c in range(len(chips))]}
                </div>}
                <div className="cm-hud">
                    {waterfall_open == idx and <span className="cm-hud-fast">{"⚡ " + fmtMs(trace["total_ms"]) + " engine"}</span>}
                    {waterfall_open == idx and <span>{("1 LLM call (routing)" if llm["sync_used"] else "0 LLM calls on the critical path")}</span>}
                    {(Number(msg["rtt_ms"]) > 0 and waterfall_open == idx) and <span>{"round trip " + fmtMs(msg["rtt_ms"])}</span>}
                    {(narr and narr["status"] == "ok" and waterfall_open == idx) and <span className="cm-hud-llm">{"✦ narrated in " + fmtMs(narr["ms"]) + " · facts guard passed"}</span>}
                    {(narr and narr["status"] == "failed" and waterfall_open == idx) and <span className="cm-muted">{"Narration unavailable — engine answer shown"}</span>}
                    {(d["privacy"] and d["privacy"]["private_turn"]) and <span className="cm-hud-private">{"Not sent to any AI model"}</span>}
                    {(d["privacy"] and d["privacy"]["words_sent_to_model"]) and <span className="cm-hud-private">{"The engine couldn't place this, so an AI model read it (identifiers removed first)"}</span>}
                    <button className="cm-why" onClick={lambda _e: MouseEvent { waterfall_open = (-1 if waterfall_open == idx else idx); }}>{(L(ui, "ui.hide_details", "Hide details") if waterfall_open == idx else L(ui, "ui.details", "Details"))}</button>
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
                <div className={("cm-bubble cm-bubble-error" if kind == "error" else "cm-bubble")}>
                    {renderRich(L(footerUi(), "ui.welcome", str(msg["text"])) if msg["id"] == "welcome" else (L(footerUi(), "ui.new_case_note", str(msg["text"])) if str(msg["id"]).startsWith("reset-") else str(msg["text"])))}
                    {(kind == "error" and is_last and msg["retry"]) and <div className="cm-retry-row"><button className="cm-why cm-retry" onClick={lambda _e: MouseEvent { sendMessage(str(msg["retry"]), str(msg["retry_answering"] or ""), str(msg["retry_display"] or ""), bool(msg["retry_pin"])); }}>Try again</button></div>}
                </div>
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
        ["Language", lang_label if lang_label else (str(p["language"]).toUpperCase() if p["language"] else "")],
        ["Income", ("$" + Number(p["income_annual"]).toLocaleString() + "/yr") if (p["income_annual"] != None and Number(p["income_annual"]) >= 0) else ""],
        ["Household", str(p["household_size"]) if Number(p["household_size"]) > 0 else ""],
        ["Age", str(p["age"]) if Number(p["age"]) > 0 else ""],
        ["Location", ((str(p["city"]) + ", ") if p["city"] else "") + str(p["state"]) if p["state"] else ""],
        ["Status", str(p["citizenship"]).replace("_", " ") if p["citizenship"] else ""]
    ];
    return
        <div className="cm-panel cm-side-card">
            <div className="cm-side-title">Case file</div>
            {(not has_case) and <div className="cm-muted" style={{"fontSize": "12px"}}>{("Nothing noted yet: tell me what you need help with." if len([m for m in messages if m["role"] == "user"]) > 0 else "Waiting for your first message…")}</div>}
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
                {pending_question and <div className="cm-next-q cm-dev-only">{"Next question: " + pending_question.replace("_", " ") + " — chosen by value of information"}</div>}
            </div>}
        </div>;
}

impl ChatPane.renderPipeline -> JsxElement {
    agents = [
        ["IntakeWalker", "intake.parse", "Language ID + parse in 75 languages, evidence spans"],
        ["LLM · understand", "chat understand_message", "Only if nothing routes · 3.5 s cap"],
        ["EligibilityWalker", "EligibilityWalker score", "2026 rules by household · Beta odds · abstention"],
        ["NavigationWalker", "NavigationWalker plan", "Smith's-rule step ordering"],
        ["PathfinderWalker", "PathfinderWalker yen_k_shortest", "Yen k-shortest expected-cost routes"],
        ["EscalationWalker", "EscalationWalker crisis_route", "Crisis lines when risk is present"],
        ["CritiqueWalker", "reflexion.critique", "Self-critique written to the graph"]
    ];
    spans: list = list(last_trace["spans"]) if (last_trace and last_trace["spans"]) else [];
    # A step that didn't run says why, so "skipped" doesn't read as "broken".
    llm_reason = str(last_llm["reason"]) if (last_llm and last_llm["reason"]) else "";
    skipped: dict = {
        "chat understand_message": ("Skipped: " + llm_reason) if llm_reason else "Not needed: the parser understood this message, so no model read it",
        "EscalationWalker crisis_route": ("Not needed: no crisis signal, and programs matched" if len([s for s in spans if s["name"] == "EligibilityWalker score"]) > 0 else "Not needed: no crisis signal, and no need named yet to score")
    };
    return
        <div className="cm-panel cm-side-card cm-dev-only" style={{"flex": "1"}}>
            <div className="cm-side-title">Agent pipeline · last turn</div>
            {[
                <div key={"ag" + str(i)} className="cm-agent">
                    <span className={("cm-agent-dot cm-agent-ran" if len([s for s in spans if s["name"] == agents[i][1]]) > 0 else "cm-agent-dot")}/>
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <div className="cm-agent-name">{agents[i][0]}</div>
                        <div className="cm-agent-role">{(skipped[agents[i][1]] if (spans and agents[i][1] in skipped and len([s for s in spans if s["name"] == agents[i][1]]) == 0) else agents[i][2])}</div>
                    </div>
                    <span className="cm-agent-ms">{(fmtMs([s for s in spans if s["name"] == agents[i][1]][0]["duration_ms"]) if len([s for s in spans if s["name"] == agents[i][1]]) > 0 else ("skipped" if (spans and agents[i][1] in skipped) else "—"))}</span>
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

impl ChatPane.forgetMe -> None {
    # Deletes this visitor's case graph on the server (ForgetWalker), then
    # the browser's anonymous login, and starts over as a new visitor.
    if not window.confirm("Delete everything this app saved about you? Your case, needs, tracked applications and answers are removed from the server, and this browser forgets its anonymous login. This can't be undone.") {
        return;
    }
    forget_state = "deleting";
    res = await safeSpawn("ForgetWalker", {"user_id": user_id});
    reps = res["reports"];
    ok = bool(reps and len(reps) > 0 and reps[len(reps) - 1]["ok"]);
    forget_state = ("done" if ok else "failed");
    if ok {
        for k in ["cm_uid", "cm_pw", "jac_token", "cm_lang"] {
            try { localStorage.removeItem(k); } except Exception as _ex {}
        }
        window.cm_quiet_leave = True;
        setTimeout(lambda { window.location.reload(); }, 1400);
    }
}

impl ChatPane.saveList(msg_id: str, matches: list, plan: Any, ui: Any) -> None {
    # Only what the person chose to keep: program names, numbers, links and
    # papers. Their own words, income and household stay out of it. On a phone
    # the share sheet can send it to Notes or a message; elsewhere it downloads.
    lines: list = [L(ui, "ui.save_head", "Programs to contact"), ""];
    for m in matches {
        lines.append(str(m["resource_name"]));
        if m["contact_phone"] { lines.append(str(m["contact_phone"])); }
        if m["online_url"] { lines.append(str(m["online_url"])); }
        lines.append("");
    }
    docs: list = list(plan["shared_documents"]) if (plan and plan["shared_documents"]) else [];
    if len(docs) > 0 {
        lines.append(L(ui, "ui.bring", "Bring") + ": " + ", ".join([str(x) for x in docs]));
        lines.append("");
    }
    lines.append("911 · 988 · 1-800-799-7233 · 211");
    text = lines.join(String.fromCharCode(10));
    saved_list = msg_id;
    window.cm_saved_list = True;
    download = lambda {
        a = document.createElement("a");
        a.href = "data:text/plain;charset=utf-8," + encodeURIComponent(text);
        a.download = "programs.txt";
        document.body.appendChild(a);
        a.click();
        a.remove();
    };
    try {
        if navigator.share {
            navigator.share({"title": lines[0], "text": text}).catch(lambda e: Any {
                # Closing the share sheet is a choice. Any other failure downloads.
                if str(e.name) != "AbortError" { download(); }
            });
            return;
        }
    } except Exception as _ex {}
    download();
}

impl ChatPane.guestTurn(fields: dict) -> Any {
    out: Any = {"reports": [], "spawn_error": "no answer"};
    r = await fetch("/walker/GuestIntakeWalker", {"method": "POST", "headers": {"Content-Type": "application/json"}, "body": JSON.stringify(fields)}).catch(lambda _e: Any { return None; });
    if r and r.status == 200 {
        j = await r.json().catch(lambda _e: Any { return None; });
        if j and j["data"] and j["data"]["reports"] { out = {"reports": j["data"]["reports"], "spawn_error": ""}; }
    }
    return out;
}

# The page says what language it is in: screen readers pick their voice from
# this, and right-to-left languages lay out from it (blind audit F22).
impl ChatPane.setPageAttrs(code: str) -> None {
    c: str = code if (code and code != "auto") else "en";
    document.documentElement.lang = c;
    document.documentElement.dir = "rtl" if c in ["ar", "fa", "ur", "ps", "ckb", "he", "yi"] else "ltr";
}

# A picked language shows at once: labels come from a small file the gateway
# serves with no account. No catalog for it: labels stay English, as answers do.
impl ChatPane.applyPageLang(code: str) -> None {
    setPageAttrs(code);
    window.cm_page_lang = code;
    if not code or code == "auto" or code == "en" { page_ui = {}; return; }
    got: Any = {};
    try {
        r = await fetch("/ui-strings/" + encodeURIComponent(code));
        if r.ok { got = await r.json(); }
    } except Exception as _ex {}
    if window.cm_page_lang == code { page_ui = got; }
}

# The lines a failed turn still shows, since the person may be in danger (audit 2026-11-06, F15).
impl ChatPane.errorLines -> str {
    u = footerUi();
    return L(u, "ui.safety_danger", "In danger now:") + " 911 · " + L(u, "ui.safety_crisis", "Suicide or crisis: call or text") + " 988 · " + L(u, "ui.safety_home", "Not safe at home:") + " 1-800-799-7233";
}

impl ChatPane.footerUi -> Any {
    if pref_lang != "auto" and page_ui and page_ui["ui.send"] { return page_ui; }
    for i in range(len(messages) - 1, -1, -1) {
        d: Any = messages[i]["data"];
        if d and d["ui"] { return d["ui"]; }
    }
    return {};
}

impl ChatPane.renderPrivacy -> JsxElement {
    return
        <details className="cm-privacy">
            <summary>
                <span className="cm-privacy-lock" aria-hidden="true"><svg width="11" height="12" viewBox="0 0 11 12"><rect x="1" y="5" width="9" height="6.5" rx="1.5" fill="currentColor"/><path d="M 3 5 V 3.6 a 2.5 2.5 0 0 1 5 0 V 5" stroke="currentColor" strokeWidth="1.4" fill="none"/></svg></span>
                {L(footerUi(), "ui.privacy_title", "Private by design — your words aren't saved or sent to AI")}
            </summary>
            <ul>
                <li>You're anonymous: this browser holds a random login, and nobody asks who you are.</li>
                <li>Your message is read on this server to find programs. It is not saved: we keep only what the engine understood (the kind of help, how urgent, household size, income).</li>
                <li>Your words are not sent to any AI model. The optional summary and translation are written from the engine's answer (program names, phone numbers, the next step), not from what you typed.</li>
                <li>Crisis messages (self-harm, abuse) are answered by fixed code.</li>
                <li>Your case is kept until you delete it, or 30 days after your last message. No advertising, no tracking, no selling.</li>
            </ul>
            <label className="cm-private-toggle">
                <input type="checkbox" checked={private_on} onChange={lambda _e: Any { setPrivate(not private_on); }}/>
                <span>{L(footerUi(), "ui.private_toggle", "Private session — keep nothing in this browser after I close the tab")}</span>
            </label>
            <div className="cm-privacy-actions">
                <a className="cm-link" href="https://github.com/Anbu-00001/CivicMesh/blob/main/PRIVACY.md" target="_blank" rel="noreferrer">Full privacy notice</a>
                <button className="cm-ghost-btn cm-danger-btn" onClick={lambda _e: MouseEvent { forgetMe(); }} disabled={forget_state == "deleting" or forget_state == "done"}>
                    {("Deleting…" if forget_state == "deleting" else ("Deleted — starting over" if forget_state == "done" else ("Couldn't delete — try again" if forget_state == "failed" else L(footerUi(), "ui.delete_data", "Delete my data"))))}
                </button>
            </div>
        </details>;
}

impl ChatPane.setPrivate(on: bool) -> None {
    # The login moves to sessionStorage (a reload in this tab still works);
    # the app shell wipes localStorage when the page closes.
    try {
        if on {
            for key in ["cm_uid", "cm_pw"] {
                v = localStorage.getItem(key);
                if v and not sessionStorage.getItem(key) { sessionStorage.setItem(key, v); }
            }
            sessionStorage.setItem("cm_private", "1");
        } else {
            for key in ["cm_uid", "cm_pw"] {
                v = sessionStorage.getItem(key);
                if v { localStorage.setItem(key, v); }
            }
            sessionStorage.removeItem("cm_private");
        }
    } except Exception as _ex {}
    private_on = on;
}
