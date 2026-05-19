"""Async implementations for the ClientApp root component."""

# Stable demo identity. The hackathon submission deliberately uses a single
# shared seed account so judges can refresh the browser and watch the same
# graph reload — that's Jac's auto-persistence demo. In production this
# would be replaced by the real auth flow (OAuth, magic links, etc.).
glob DEMO_USER_ID: str = "demo_user";
glob DEMO_USER_PASSWORD: str = "civicmesh2026";

impl ClientApp.initAuth -> None {
    ok = await jacLogin(DEMO_USER_ID, DEMO_USER_PASSWORD);
    if not ok {
        await jacSignup(DEMO_USER_ID, DEMO_USER_PASSWORD);
        ok = await jacLogin(DEMO_USER_ID, DEMO_USER_PASSWORD);
    }
    if ok {
        is_authed = True;
        user_id = DEMO_USER_ID;
        # Bootstrap the user's per-root resource catalog. jac-scale gives
        # every authenticated user their own root, so we must seed the 40
        # ResourceNodes into THIS user's graph before EligibilityWalker
        # has anything to score against. The walker is idempotent — second
        # run just reports skipped == 40.
        try {
            await root spawn SeedWalker(user_id=DEMO_USER_ID);
        } except Exception as _ex {
            # Seed failure is non-fatal — the chat will still load, just
            # with zero matches until the server is restarted with the data
            # file in a reachable location.
            is_authed = is_authed;
        }
    } else {
        is_authed = False;
    }
}

impl ClientApp.loadSession -> None {
    # Always re-run SeedWalker on session load so an already-authed user
    # whose root predates the demo-apps feature still picks them up on
    # next refresh. SeedWalker is idempotent — duplicate resource and
    # leads_to insertion is guarded; demo apps only seed when the
    # PersonNode has zero existing ApplicationNodes attached.
    try {
        await root spawn SeedWalker(user_id=user_id);
    } except Exception as _ex {}

    try {
        result = await root spawn MemoryWalker(
            user_id=user_id,
            mode="read_session"
        );
        raw = result.reports[0] if result.reports else None;
        if raw {
            session_data = raw;
        } else {
            session_data = {};
        }
    } except Exception as e {
        session_data = {};
    }
}

impl ClientApp.startApp -> None {
    # CTA from the landing page hides it and routes the user to the chat tab.
    # Auth runs on mount (initAuth in `with entry`). If it hasn't finished
    # yet, ChatPane's sendMessage will retry — don't block the UI here.
    show_landing = False;
    active_tab = "chat";
}

impl ClientApp.pushWalkerEvent(events: list) -> None {
    # Receives the FULL accumulated events list each call (not a delta).
    # This sidesteps React closure staleness when sendMessage fires many
    # updates in one synchronous burst — each call sets walker_events to
    # the full known list, so the last winner contains everything.
    walker_events = events;
}

impl ClientApp.navTab(tab_id: str, label: str) -> JsxElement {
    is_active = active_tab == tab_id;
    return
        <button
            onClick={lambda _e: MouseEvent { active_tab = tab_id; }}
            style={{
                "padding": "7px 14px",
                "background": ("#FFE500" if is_active else "transparent"),
                "color": ("#0A0A0A" if is_active else "rgba(255,255,255,0.55)"),
                "border": "none",
                "borderRadius": "8px",
                "fontSize": "13px",
                "fontWeight": ("600" if is_active else "500"),
                "cursor": "pointer",
                "transition": "all 0.2s ease",
                "display": "flex",
                "alignItems": "center",
                "gap": "7px"
            }}
        >
            {tabIcon(tab_id, is_active)}
            {label}
        </button>;
}

impl ClientApp.tabIcon(tab_id: str, is_active: bool) -> JsxElement {
    # Inline SVG traced icons — no emoji, no image files. Stroke color
    # tracks the active state so the active tab's black on yellow stays
    # visible while inactive tabs use a faded white.
    stroke = "#0A0A0A" if is_active else "rgba(255,255,255,0.7)";
    if tab_id == "chat" {
        # Speech bubble outline with a tail
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <path
                    d="M4 6.5 C 4 5.1 5.1 4 6.5 4 L 17.5 4 C 18.9 4 20 5.1 20 6.5 L 20 14 C 20 15.4 18.9 16.5 17.5 16.5 L 11 16.5 L 7 20 L 7 16.5 L 6.5 16.5 C 5.1 16.5 4 15.4 4 14 Z"
                    stroke={stroke}
                    strokeWidth="1.8"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                />
            </svg>;
    }
    if tab_id == "graph" {
        # Three connected nodes
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <circle cx="6" cy="6" r="2.5" stroke={stroke} strokeWidth="1.8"/>
                <circle cx="18" cy="8" r="2.5" stroke={stroke} strokeWidth="1.8"/>
                <circle cx="12" cy="18" r="2.5" stroke={stroke} strokeWidth="1.8"/>
                <path d="M8 7.5 L 15.5 8 M 17 10.5 L 13 15.5 M 7.5 8 L 10.5 16" stroke={stroke} strokeWidth="1.5" strokeLinecap="round"/>
            </svg>;
    }
    if tab_id == "plan" {
        # Checklist (rectangle + three rows + a check)
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <rect x="4" y="3" width="16" height="18" rx="2" stroke={stroke} strokeWidth="1.8"/>
                <path d="M8 8 L 10 10 L 13 7" stroke={stroke} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
                <path d="M8 14 L 16 14 M 8 17.5 L 14 17.5" stroke={stroke} strokeWidth="1.6" strokeLinecap="round"/>
            </svg>;
    }
    if tab_id == "telemetry" {
        # Bar chart, three ascending bars
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <rect x="4" y="13" width="3.5" height="7" rx="0.6" stroke={stroke} strokeWidth="1.6"/>
                <rect x="10.25" y="9" width="3.5" height="11" rx="0.6" stroke={stroke} strokeWidth="1.6"/>
                <rect x="16.5" y="5" width="3.5" height="15" rx="0.6" stroke={stroke} strokeWidth="1.6"/>
            </svg>;
    }
    if tab_id == "impact" {
        # Heart outline — anchors the Impact tab to its outcomes story
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <path
                    d="M12 20 C 7 16 3 13 3 9 C 3 6 5.5 4 8 4 C 10 4 11.5 5 12 7 C 12.5 5 14 4 16 4 C 18.5 4 21 6 21 9 C 21 13 17 16 12 20 Z"
                    stroke={stroke}
                    strokeWidth="1.6"
                    strokeLinejoin="round"
                />
            </svg>;
    }
    return <span/>;
}

impl ClientApp.togglePalette -> None {
    palette_open = (not palette_open);
    palette_query = "";
    palette_idx = 0;
}

impl ClientApp.runPaletteAction(action: Any) -> None {
    # Single dispatch site so the keyboard handler and the mouse click both
    # route through one place. Closes the palette after every action so the
    # user gets back to the work surface immediately.
    kind = str(action["kind"]);
    payload = str(action["payload"]);
    if kind == "tab" {
        active_tab = payload;
    } elif kind == "replay" {
        # Cheap "replay" — toggle the active tab to graph; the GraphViz
        # component's own Replay button is the canonical trigger and is
        # right there once you land.
        active_tab = "graph";
    } elif kind == "docs" {
        # Open the jac-scale auto-generated OpenAPI page in a new tab.
        # `window.open` is a JS builtin; jac compiles the bare name through.
        try {
            window.open("http://localhost:8001/docs", "_blank");
        } except Exception as _ex {}
    } elif kind == "reset" {
        # Reset the live walker_events buffer so the graph + telemetry
        # tabs show a clean slate without forcing a full page reload.
        walker_events = [];
    }
    palette_open = False;
    palette_query = "";
    palette_idx = 0;
}

impl ClientApp.renderPaletteItem(action: Any, idx: int, sel: int) -> JsxElement {
    label = str(action["label"]);
    is_selected = idx == sel;
    return
        <div
            key={label}
            onClick={lambda _e: MouseEvent { runPaletteAction(action); }}
            onMouseEnter={lambda _e: MouseEvent { palette_idx = idx; }}
            style={{
                "padding": "10px 14px",
                "borderRadius": "8px",
                "background": ("rgba(255,229,0,0.1)" if is_selected else "transparent"),
                "border": ("0.5px solid rgba(255,229,0,0.35)" if is_selected else "0.5px solid transparent"),
                "color": ("#FFE500" if is_selected else "rgba(255,255,255,0.8)"),
                "fontSize": "13px",
                "cursor": "pointer",
                "display": "flex",
                "alignItems": "center",
                "gap": "10px",
                "transition": "all 0.12s ease"
            }}
        >
            <span style={{
                "fontFamily": "ui-monospace, monospace",
                "fontSize": "10px",
                "color": ("#FFE500" if is_selected else "rgba(255,255,255,0.3)"),
                "minWidth": "16px"
            }}>
                {"›"}
            </span>
            <span style={{"flex": "1"}}>{label}</span>
            {is_selected and <span style={{
                "fontSize": "9px",
                "fontFamily": "ui-monospace, monospace",
                "padding": "2px 6px",
                "background": "rgba(255,229,0,0.15)",
                "border": "0.5px solid rgba(255,229,0,0.3)",
                "borderRadius": "4px",
                "color": "#FFE500",
                "letterSpacing": "0.04em"
            }}>
                ENTER
            </span>}
        </div>;
}

impl ClientApp.renderPalette -> JsxElement {
    # Fuzzy substring filter — case-insensitive, no scoring beyond "contains".
    # Keeps the implementation tiny and predictable; the action list is short
    # enough that a fancier ranking would be lost on the user.
    q = palette_query.lower().strip();
    filtered: list = [];
    for a in palette_actions {
        lbl_lower = str(a["label"]).lower();
        if (not q) or (q in lbl_lower) {
            filtered = filtered + [a];
        }
    }
    sel = palette_idx;
    if sel >= len(filtered) and len(filtered) > 0 {
        sel = 0;
    }

    return
        <div
            onClick={lambda _e: MouseEvent { togglePalette(); }}
            style={{
                "position": "fixed",
                "inset": "0",
                "zIndex": "1000",
                "background": "rgba(5,5,8,0.65)",
                "backdropFilter": "blur(8px)",
                "display": "flex",
                "alignItems": "flex-start",
                "justifyContent": "center",
                "paddingTop": "14vh"
            }}
        >
            <div
                onClick={lambda e: MouseEvent { e.stopPropagation(); }}
                style={{
                    "width": "560px",
                    "maxWidth": "92vw",
                    "background": "linear-gradient(180deg, rgba(20,20,24,0.95), rgba(12,12,16,0.95))",
                    "border": "0.5px solid rgba(255,255,255,0.12)",
                    "borderRadius": "14px",
                    "boxShadow": "0 32px 72px -20px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,229,0,0.06)",
                    "overflow": "hidden"
                }}
            >
                <div style={{"padding": "14px 16px 10px", "borderBottom": "0.5px solid rgba(255,255,255,0.06)", "display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" style={{"flexShrink": "0"}}>
                        <circle cx="11" cy="11" r="6.5" stroke="rgba(255,229,0,0.6)" strokeWidth="1.6"/>
                        <path d="M16 16 L 20 20" stroke="rgba(255,229,0,0.6)" strokeWidth="1.6" strokeLinecap="round"/>
                    </svg>
                    <input
                        value={palette_query}
                        onChange={lambda e: ChangeEvent { palette_query = e.target.value; palette_idx = 0; }}
                        onKeyDown={lambda e: KeyboardEvent {
                            if e.key == "ArrowDown" {
                                e.preventDefault();
                                if palette_idx + 1 < len(filtered) { palette_idx = palette_idx + 1; }
                            } elif e.key == "ArrowUp" {
                                e.preventDefault();
                                if palette_idx > 0 { palette_idx = palette_idx - 1; }
                            } elif e.key == "Enter" {
                                e.preventDefault();
                                if len(filtered) > 0 {
                                    runPaletteAction(filtered[sel]);
                                }
                            } elif e.key == "Escape" {
                                togglePalette();
                            }
                        }}
                        placeholder="Type a command — tabs, replay, docs, reset..."
                        autoFocus={True}
                        style={{
                            "flex": "1",
                            "background": "transparent",
                            "border": "none",
                            "outline": "none",
                            "color": "#FFFFFF",
                            "fontSize": "14px",
                            "fontFamily": "system-ui, sans-serif"
                        }}
                    />
                    <span style={{
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.35)",
                        "fontFamily": "ui-monospace, monospace",
                        "padding": "3px 7px",
                        "background": "rgba(255,255,255,0.04)",
                        "border": "0.5px solid rgba(255,255,255,0.1)",
                        "borderRadius": "5px"
                    }}>
                        ESC
                    </span>
                </div>
                <div style={{"padding": "8px", "maxHeight": "50vh", "overflowY": "auto", "display": "flex", "flexDirection": "column", "gap": "2px"}}>
                    {(len(filtered) == 0) and <div style={{"padding": "20px", "textAlign": "center", "fontSize": "12px", "color": "rgba(255,255,255,0.4)"}}>
                        No matching commands.
                    </div>}
                    {[renderPaletteItem(filtered[i], i, sel) for i in range(len(filtered))]}
                </div>
                <div style={{
                    "padding": "8px 16px",
                    "borderTop": "0.5px solid rgba(255,255,255,0.06)",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "12px",
                    "fontSize": "10px",
                    "color": "rgba(255,255,255,0.4)",
                    "fontFamily": "ui-monospace, monospace"
                }}>
                    <span>↑↓ navigate</span>
                    <span>↵ run</span>
                    <span>esc close</span>
                    <span style={{"flex": "1"}}/>
                    <span>{str(len(filtered)) + " action" + ("" if len(filtered) == 1 else "s")}</span>
                </div>
            </div>
        </div>;
}
