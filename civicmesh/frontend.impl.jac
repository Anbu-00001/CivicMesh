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

impl ClientApp.startApp -> None {
    # CTA from the landing page hides it and routes the user to the chat tab.
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
