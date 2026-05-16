"""CivicMesh — entry point.
sv section: imports all walkers so jac-scale registers them as endpoints.
cl section: root app component with tab navigation.
"""

to sv:

import from graph.nodes { PersonNode, NeedNode, ResourceNode,
    EligibilityRuleNode, FormNode, ApplicationNode }
import from graph.edges { has_need, eligible_for, governed_by,
    requires_form, applied_to }
import from llm.stubs { NeedProfile, EligibilityResult, ActionStep,
    ActionPlan, EscalationContext, EscalationMessage,
    LanguageProfile, SessionSummary }
import from walkers.intake { IntakeWalker }
import from walkers.eligibility { EligibilityWalker }
import from walkers.navigation { NavigationWalker }
import from walkers.memory { MemoryWalker }
import from walkers.escalation { EscalationWalker }

to cl:

import from "@jac/runtime" { jacLogin, jacSignup, jacIsLoggedIn }
import from .components.ChatPane { ChatPane }
import from .components.GraphViz { GraphViz }
import from .components.ActionPlan { ActionPlan }
import from .components.SessionBanner { SessionBanner }
import from .components.TelemetryPanel { TelemetryPanel }
sv import from walkers.memory { MemoryWalker }

def:pub app -> JsxElement {
    has active_tab: str = "chat",
        is_authed: bool = False,
        user_id: str = "demo_user",
        session_data: dict = {},
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

    return
        <div
            style={{
                "minHeight": "100vh",
                "background": "#0A0A0A",
                "color": "#FFFFFF",
                "fontFamily": "system-ui, -apple-system, sans-serif"
            }}
        >
            <div
                style={{
                    "position": "absolute",
                    "top": "-15%",
                    "left": "-5%",
                    "width": "50%",
                    "height": "50%",
                    "background": "radial-gradient(circle, rgba(255,229,0,0.05) 0%, transparent 70%)",
                    "pointerEvents": "none"
                }}
            />
            <div
                style={{
                    "position": "absolute",
                    "bottom": "-15%",
                    "right": "-5%",
                    "width": "40%",
                    "height": "40%",
                    "background": "radial-gradient(circle, rgba(255,229,0,0.03) 0%, transparent 70%)",
                    "pointerEvents": "none"
                }}
            />
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
            {session_data.get("has_history", False)
                and <SessionBanner session_data={session_data}/>}
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
