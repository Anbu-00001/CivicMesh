"""CivicMesh frontend root.
Contains the actual `app` component. Lives in its own file so that the
sv-side walker imports (in app.jac) never collide with the client-side
`sv import` RPC stubs declared here.
"""

cl import ".assets/index.css";

# Each browser gets its own account (random id + secret in localStorage), so
# visitors never share one graph. Globs must live in the .cl.jac to reach the
# production client bundle.
glob VISITOR_KEY: str = "cm_uid";
glob VISITOR_SECRET_KEY: str = "cm_pw";

import from "@jac/runtime" { jacLogin, jacSignup, jacIsLoggedIn, jacSpawn }
import from .components.ChatPane { ChatPane }
import from .components.GraphViz { GraphViz }
import from .components.ActionPlan { ActionPlan }
import from .components.SessionBanner { SessionBanner }
import from .components.TelemetryPanel { TelemetryPanel }
import from .components.LandingPage { LandingPage }
import from .components.ImpactReport { ImpactReport }

sv import from walkers.memory { MemoryWalker }
sv import from walkers.seed { SeedWalker }
sv import from walkers.platform { PlatformWalker }

# Quick exit (GOV.UK "Exit this page" pattern): Shift pressed 3 times within
# 5 seconds, or the button. Not Escape: it also stops a page load.
glob CM_SHIFTS: dict = {"t": []};
glob CM_EXIT_URL: str = "https://weather.com/";

def:pub ClientApp -> JsxElement {
    has active_tab: str = "chat",
        is_authed: bool = False,
        user_id: str = "",
        session_data: Any = {},
        walker_events: list = [],
        show_landing: bool = True,
        palette_open: bool = False,
        palette_query: str = "",
        palette_idx: int = 0,
        # Live engine preview + platform counters for the landing page.
        platform: Any = None;

    # Master action list for the Cmd+K command palette. Each entry is a
    # (label, kind, payload) triple so navigate actions and side effects
    # share a single dispatch path in runPaletteAction.
    palette_actions: list[dict] = [
        {"label": "Switch to Chat tab",        "kind": "tab",    "payload": "chat"},
        {"label": "Switch to Graph tab",       "kind": "tab",    "payload": "graph"},
        {"label": "Switch to Action Plan tab", "kind": "tab",    "payload": "plan"},
        {"label": "Switch to Telemetry tab",   "kind": "tab",    "payload": "telemetry"},
        {"label": "Switch to Impact tab",      "kind": "tab",    "payload": "impact"},
        {"label": "Replay walker chain",       "kind": "replay", "payload": ""},
        {"label": "Show /docs OpenAPI",        "kind": "docs",   "payload": ""},
        {"label": "Reset session",             "kind": "reset",  "payload": ""}
    ];

    def startApp -> None;
    def togglePalette -> None;
    def runPaletteAction(action: Any) -> None;
    def renderPaletteItem(action: Any, idx: int, sel: int) -> JsxElement;
    def renderPalette -> JsxElement;

    can with entry {
        # Always run initAuth: it also migrates browsers still holding the
        # old shared demo token onto their own visitor account.
        initAuth();
        # Global Cmd/Ctrl+K listener wired at the document level so the
        # palette is reachable from any tab without per-component plumbing.
        try {
            document.addEventListener("keydown", lambda e: KeyboardEvent {
                k_raw = e.key;
                k = str(k_raw) if k_raw else "";
                is_k = k == "k" or k == "K";
                meta_flag = bool(e.metaKey);
                ctrl_flag = bool(e.ctrlKey);
                if is_k and (meta_flag or ctrl_flag) {
                    e.preventDefault();
                    palette_open = (not palette_open);
                    palette_query = "";
                    palette_idx = 0;
                } elif palette_open and k == "Escape" {
                    palette_open = False;
                }
                if k == "Shift" and not e.repeat {
                    now = Date.now();
                    kept: list = [t for t in list(CM_SHIFTS["t"]) if now - Number(t) < 5000];
                    kept.append(now);
                    CM_SHIFTS["t"] = kept;
                    if len(CM_SHIFTS["t"]) >= 3 { quickExit(); }
                }
            });
            # A private session (crisis turns switch it on) leaves nothing in
            # this browser once the page closes: the login lives in
            # sessionStorage and localStorage is wiped on the way out.
            window.addEventListener("pagehide", lambda _e: Any {
                try {
                    if sessionStorage.getItem("cm_private") == "1" {
                        for key in ["cm_uid", "cm_pw", "jac_token", "cm_lang"] { localStorage.removeItem(key); }
                    }
                } except Exception as _ex {}
            });
        } except Exception as _ex {
            # Document-level listener unavailable — palette is still
            # reachable via the nav button. Swallow silently; nothing to do.
            palette_open = palette_open;
        }
    }

    can with [is_authed] entry {
        if is_authed {
            loadSession();
        }
    }

    async def initAuth -> None;
    def visitorCreds -> list;
    def quickExit -> None;
    async def loadSession -> None;
    def pushWalkerEvent(events: list) -> None;
    def navTab(tab_id: str, label: str) -> JsxElement;
    def tabIcon(tab_id: str, is_active: bool) -> JsxElement;

    # Build has_history defensively without using .get (Any-typed value doesn't expose .get to the checker)
    has_history = False;
    if session_data {
        try {
            has_history = bool(session_data["has_history"]);
        } except Exception as _ex {
            has_history = False;
        }
    }

    if show_landing {
        return <LandingPage on_start={startApp} platform={platform}/>;
    }

    return
        <div
            style={{
                "minHeight": "100vh",
                "display": "flex",
                "flexDirection": "column",
                "background": "#0A0A0A",
                "color": "#FFFFFF",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}
        >
            <div className="aurora-blob aurora-blob-1"/>
            <div className="aurora-blob aurora-blob-2"/>
            <div className="aurora-blob aurora-blob-3"/>
            <header
                className="cm-appbar"
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
                    <h1
                        style={{
                            "fontSize": "17px",
                            "fontWeight": "700",
                            "letterSpacing": "-0.03em",
                            "color": "#FFE500",
                            "margin": "0"
                        }}
                    >
                        CivicMesh
                    </h1>
                    <span
                        className="cm-appbar-badge"
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
                    className="cm-appnav"
                    style={{
                        "display": "flex",
                        "gap": "3px",
                        "padding": "4px",
                        "background": "rgba(255,255,255,0.04)",
                        "borderRadius": "10px",
                        "border": "0.5px solid rgba(255,255,255,0.07)"
                    }}
                >
                    {navTab("chat", "Chat")}
                    {navTab("graph", "Graph")}
                    {navTab("plan", "Action Plan")}
                    {navTab("telemetry", "Telemetry")}
                    {navTab("impact", "Impact")}
                </nav>
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <button className="cm-quick-exit" onClick={lambda _e: MouseEvent { quickExit(); }} title="Leave this site right now (or press Shift three times)">Quick exit</button>
                    <button
                        onClick={lambda _e: MouseEvent { togglePalette(); }}
                        title="Open command palette (⌘K)"
                        aria-label="Open command palette"
                        style={{
                            "display": "flex",
                            "alignItems": "center",
                            "gap": "6px",
                            "padding": "5px 9px 5px 10px",
                            "background": "rgba(255,255,255,0.04)",
                            "border": "0.5px solid rgba(255,255,255,0.1)",
                            "borderRadius": "8px",
                            "color": "rgba(255,255,255,0.55)",
                            "fontSize": "11px",
                            "cursor": "pointer",
                            "fontFamily": "ui-monospace, monospace"
                        }}
                    >
                        <svg width="11" height="11" viewBox="0 0 24 24" fill="none">
                            <circle cx="11" cy="11" r="6.5" stroke="currentColor" strokeWidth="1.8"/>
                            <path d="M16 16 L 20 20" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
                        </svg>
                        <span style={{"letterSpacing": "0.04em"}}>⌘K</span>
                    </button>
                    <span
                        style={{
                            "width": "6px",
                            "height": "6px",
                            "borderRadius": "50%",
                            "background": ("#00FF88" if is_authed else "#FFB344"),
                            "display": "inline-block"
                        }}
                    />
                    <span style={{"fontSize": "12px", "color": "rgba(255,255,255,0.62)"}}>
                        {("engine ready · LLM narrator" if is_authed else "connecting...")}
                    </span>
                </div>
            </header>
            {has_history and <SessionBanner session_data={session_data}/>}
            <main
                style={{
                    "padding": "12px 28px 20px 28px",
                    "maxWidth": "1400px",
                    "width": "100%",
                    "margin": "0 auto",
                    "position": "relative",
                    "zIndex": "1",
                    "flex": "1"
                }}
            >
                {active_tab == "chat" and <ChatPane
                    user_id={user_id}
                    on_walker_event={pushWalkerEvent}
                    session_data={session_data}
                    walker_events={walker_events}
                    platform={platform}
                />}
                {active_tab == "graph" and <GraphViz walker_events={walker_events} user_id={user_id}/>}
                {active_tab == "plan" and <ActionPlan user_id={user_id} walker_events={walker_events}/>}
                {active_tab == "telemetry" and <TelemetryPanel walker_events={walker_events} user_id={user_id}/>}
                {active_tab == "impact" and <ImpactReport/>}
            </main>
            <footer
                className="cm-appfooter"
                style={{
                    "padding": "12px 28px",
                    "gap": "16px",
                    "flexWrap": "wrap",
                    "borderTop": "0.5px solid rgba(255,255,255,0.05)",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "space-between",
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.55)",
                    "maxWidth": "1400px",
                    "margin": "0 auto"
                }}
            >
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <span>CivicMesh · Agentic AI Navigator</span>
                    <span style={{"opacity": "0.5"}}>·</span>
                    <span>{"Jac walkers · " + str(len(walker_events)) + " events this session"}</span>
                </div>
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <span>Powered by Jac · jac-scale · byllm</span>
                </div>
            </footer>
            {palette_open and renderPalette()}
        </div>;
}
