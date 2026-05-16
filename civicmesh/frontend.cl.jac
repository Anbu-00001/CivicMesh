"""CivicMesh frontend root.
Contains the actual `app` component. Lives in its own file so that the
sv-side walker imports (in app.jac) never collide with the client-side
`sv import` RPC stubs declared here.
"""

cl import ".assets/index.css";

import from "@jac/runtime" { jacLogin, jacSignup, jacIsLoggedIn }
import from .components.ChatPane { ChatPane }
import from .components.GraphViz { GraphViz }
import from .components.ActionPlan { ActionPlan }
import from .components.SessionBanner { SessionBanner }
import from .components.TelemetryPanel { TelemetryPanel }

sv import from walkers.memory { MemoryWalker }

def:pub ClientApp -> JsxElement {
    has active_tab: str = "chat",
        is_authed: bool = False,
        user_id: str = "demo_user",
        session_data: Any = {},
        walker_events: list = [];

    can with entry {
        authed_now = jacIsLoggedIn();
        is_authed = authed_now;
        if not authed_now {
            initAuth();
        }
    }

    can with [is_authed] entry {
        if is_authed {
            loadSession();
        }
    }

    async def initAuth -> None;
    async def loadSession -> None;
    def pushWalkerEvent(event: dict) -> None;

    def navTab(tab_id: str, label: str, icon: str) -> JsxElement {
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

    # Build has_history defensively without using .get (Any-typed value doesn't expose .get to the checker)
    has_history = False;
    if session_data {
        try {
            has_history = bool(session_data["has_history"]);
        } except Exception as _ex {
            has_history = False;
        }
    }

    return
        <div
            style={{
                "minHeight": "100vh",
                "background": "#0A0A0A",
                "color": "#FFFFFF",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}
        >
            <div className="aurora-blob aurora-blob-1"/>
            <div className="aurora-blob aurora-blob-2"/>
            <div className="aurora-blob aurora-blob-3"/>
            <header
                style={{
                    "padding": "0 24px",
                    "height": "54px",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "space-between",
                    "borderBottom": "0.5px solid rgba(255,255,255,0.07)",
                    "background": "rgba(10,10,10,0.85)",
                    "backdropFilter": "blur(12px)",
                    "position": "relative",
                    "zIndex": "10"
                }}
            >
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <span
                        style={{
                            "fontSize": "17px",
                            "fontWeight": "700",
                            "letterSpacing": "-0.03em",
                            "color": "#FFE500"
                        }}
                    >
                        CivicMesh
                    </span>
                    <span
                        style={{
                            "fontSize": "11px",
                            "padding": "2px 8px",
                            "borderRadius": "20px",
                            "background": "rgba(255,229,0,0.1)",
                            "color": "#FFE500",
                            "border": "0.5px solid rgba(255,229,0,0.25)"
                        }}
                    >
                        Agentic AI Navigator
                    </span>
                </div>
                <nav
                    style={{
                        "display": "flex",
                        "gap": "3px",
                        "padding": "4px",
                        "background": "rgba(255,255,255,0.04)",
                        "borderRadius": "10px",
                        "border": "0.5px solid rgba(255,255,255,0.07)"
                    }}
                >
                    {navTab("chat", "Chat", "💬")}
                    {navTab("graph", "Graph", "🕸")}
                    {navTab("plan", "Action Plan", "✅")}
                    {navTab("telemetry", "Telemetry", "📊")}
                </nav>
                <div style={{"display": "flex", "alignItems": "center", "gap": "7px"}}>
                    <span
                        style={{
                            "width": "6px",
                            "height": "6px",
                            "borderRadius": "50%",
                            "background": ("#00FF88" if is_authed else "#FFB344"),
                            "display": "inline-block"
                        }}
                    />
                    <span style={{"fontSize": "12px", "color": "rgba(255,255,255,0.4)"}}>
                        {("llama-3.1-8b · connected" if is_authed else "connecting...")}
                    </span>
                </div>
            </header>
            {has_history and <SessionBanner session_data={session_data}/>}
            <main
                style={{
                    "padding": "20px 24px",
                    "maxWidth": "1200px",
                    "margin": "0 auto",
                    "position": "relative",
                    "zIndex": "1"
                }}
            >
                {(<ChatPane
                    user_id={user_id}
                    on_walker_event={pushWalkerEvent}
                    session_data={session_data}
                />) if active_tab == "chat" else None}
                {(<GraphViz walker_events={walker_events}/>) if active_tab == "graph" else None}
                {(<ActionPlan user_id={user_id}/>) if active_tab == "plan" else None}
                {(<TelemetryPanel walker_events={walker_events}/>) if active_tab == "telemetry" else None}
            </main>
        </div>;
}
