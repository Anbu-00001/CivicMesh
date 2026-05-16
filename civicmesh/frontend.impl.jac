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

impl ClientApp.pushWalkerEvent(event: dict) -> None {
    walker_events = walker_events + [event];
}
