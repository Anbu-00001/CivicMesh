"""Async implementations for the ClientApp root component."""

impl ClientApp.initAuth -> None {
    ok = await jacLogin("demo_user", "civicmesh2026");
    if not ok {
        await jacSignup("demo_user", "civicmesh2026");
        ok = await jacLogin("demo_user", "civicmesh2026");
    }
    if ok {
        is_authed = True;
        user_id = "demo_user";
    } else {
        is_authed = False;
    }
}

impl ClientApp.loadSession -> None {
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

impl ClientApp.pushWalkerEvent(events: list) -> None {
    # Receives the FULL accumulated events list each call (not a delta).
    # This sidesteps React closure staleness when sendMessage fires many
    # updates in one synchronous burst — each call sets walker_events to
    # the full known list, so the last winner contains everything.
    walker_events = events;
}

impl ClientApp.navTab(tab_id: str, label: str, icon: str) -> JsxElement {
    is_active = active_tab == tab_id;
    return
        <button
            onClick={lambda _e: MouseEvent { active_tab = tab_id; }}
            style={{
                "padding": "7px 16px",
                "background": ("#FFE500" if is_active else "transparent"),
                "color": ("#0A0A0A" if is_active else "rgba(255,255,255,0.45)"),
                "border": "none",
                "borderRadius": "8px",
                "fontSize": "13px",
                "fontWeight": ("600" if is_active else "400"),
                "cursor": "pointer",
                "transition": "all 0.2s ease",
                "display": "flex",
                "alignItems": "center",
                "gap": "5px"
            }}
        >
            <span>{icon}</span>
            {label}
        </button>;
}
