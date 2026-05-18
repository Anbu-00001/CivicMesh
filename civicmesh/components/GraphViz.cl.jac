"""Live graph traversal visualization.
Node types match Phase 1 schema exactly.
Replay animates the walker path step by step.
"""

def:pub GraphViz(walker_events: list) -> JsxElement {
    has visited: list[str] = [],
        current: str = "",
        is_playing: bool = False,
        replay_idx: int = 0,
        hovered_node: str = "",
        show_why_path: bool = False;

    # Node definitions — match Phase 1 schema exactly. Each node also carries
    # a `tooltip` line explaining what the walker discovered at this node;
    # this is what hover surfaces so the graph stops being decorative.
    has graph_nodes: list[dict] = [
        {"id": "root",    "type": "Root",                  "label": "root",      "x": 340, "y": 40,
         "walker": "—",                "tooltip": "Graph entry point — every walker spawns from here."},
        {"id": "person",  "type": "PersonNode",            "label": "Person",    "x": 340, "y": 130,
         "walker": "MemoryWalker",     "tooltip": "Session-persistent identity — user_id, language, history."},
        {"id": "need",    "type": "NeedNode",              "label": "Need",      "x": 340, "y": 220,
         "walker": "IntakeWalker",     "tooltip": "Extracted NeedProfile · category + urgency from free-form text."},
        {"id": "r1",      "type": "ResourceNode",          "label": "Section 8", "x": 100, "y": 330,
         "walker": "EligibilityWalker","tooltip": "Section 8 housing voucher · scored vs. profile."},
        {"id": "r2",      "type": "ResourceNode",          "label": "SNAP",      "x": 210, "y": 330,
         "walker": "EligibilityWalker","tooltip": "SNAP food benefits · ~$240/mo if eligible."},
        {"id": "r3",      "type": "ResourceNode",          "label": "WIC",       "x": 340, "y": 330,
         "walker": "EligibilityWalker","tooltip": "WIC nutrition for women + children under 5."},
        {"id": "r4",      "type": "ResourceNode",          "label": "LIHEAP",    "x": 460, "y": 330,
         "walker": "EligibilityWalker","tooltip": "Low-income heating + cooling utility assistance."},
        {"id": "r5",      "type": "ResourceNode",          "label": "HCH",       "x": 570, "y": 330,
         "walker": "EligibilityWalker","tooltip": "Health Care for the Homeless · free clinic."},
        {"id": "e1",      "type": "EligibilityRuleNode",   "label": "Rule §8",   "x": 100, "y": 430,
         "walker": "EligibilityWalker","tooltip": "Rule: income < 50% AMI · family size ≥ 1 · check_eligibility() match."},
        {"id": "e2",      "type": "EligibilityRuleNode",   "label": "Rule SNAP", "x": 210, "y": 430,
         "walker": "EligibilityWalker","tooltip": "Rule: gross income ≤ 130% FPL · resource limit applies."},
        {"id": "e3",      "type": "EligibilityRuleNode",   "label": "Rule WIC",  "x": 340, "y": 430,
         "walker": "EligibilityWalker","tooltip": "Rule: pregnant/postpartum/child under 5 · income ≤ 185% FPL."},
        {"id": "f1",      "type": "FormNode",              "label": "Form §8",   "x": 100, "y": 520,
         "walker": "NavigationWalker", "tooltip": "Form template · prefilled from PersonNode session fields."},
        {"id": "app1",    "type": "ApplicationNode",       "label": "Applied",   "x": 220, "y": 520,
         "walker": "NavigationWalker", "tooltip": "ApplicationNode · status='applied' · persisted via applied_to edge."},
        {"id": "app2",    "type": "ApplicationNode",       "label": "Pending",   "x": 340, "y": 520,
         "walker": "NavigationWalker", "tooltip": "ApplicationNode · status='pending' · awaiting review."}
    ];

    # Each edge carries a semantic relation label that becomes visible when
    # the user toggles "Why this path?". Labels mirror the schema's actual
    # edge types so the graph reads as a real knowledge graph, not decor.
    has graph_edges: list[dict] = [
        {"src": "root",    "tgt": "person", "label": "owns"},
        {"src": "person",  "tgt": "need",   "label": "has_need"},
        {"src": "need",    "tgt": "r1",     "label": "qualifies_for"},
        {"src": "need",    "tgt": "r2",     "label": "qualifies_for"},
        {"src": "need",    "tgt": "r3",     "label": "qualifies_for"},
        {"src": "need",    "tgt": "r4",     "label": "qualifies_for"},
        {"src": "need",    "tgt": "r5",     "label": "qualifies_for"},
        {"src": "r1",      "tgt": "e1",     "label": "governed_by"},
        {"src": "r2",      "tgt": "e2",     "label": "governed_by"},
        {"src": "r3",      "tgt": "e3",     "label": "governed_by"},
        {"src": "e1",      "tgt": "f1",     "label": "requires_form"},
        {"src": "person",  "tgt": "app1",   "label": "applied_to"},
        {"src": "person",  "tgt": "app2",   "label": "applied_to"}
    ];

    has walk_path: list[str] = [
        "root","person","need",
        "r1","e1","f1",
        "r2","e2",
        "r3","e3",
        "r4","r5",
        "app1","app2"
    ];

    # Map each walker name to the graph nodes it visits when it fires.
    # This is how we derive the REAL traversal path from the live event
    # stream — not a hardcoded replay animation.
    walker_to_nodes: dict = {
        "IntakeWalker":      ["root", "person", "need"],
        "EligibilityWalker": ["r1", "r2", "r3", "r4", "r5"],
        "NavigationWalker":  ["e1", "e2", "e3", "f1"],
        "MemoryWalker":      ["app1", "app2"],
        "EscalationWalker":  []
    };

    can with [walker_events] entry {
        if walker_events {
            # Recompute the visited set from the full event stream so the
            # graph shows the actual walker chain that ran for this session.
            fired: list = [];
            ev_count = len(walker_events);
            i = 0;
            while i < ev_count {
                ev: Any = walker_events[i];
                w_raw = ev["walker"] if ev else "";
                w = str(w_raw) if w_raw else "";
                if w and (w not in fired) {
                    fired = fired + [w];
                }
                i = i + 1;
            }
            real_path: list = [];
            for w in fired {
                node_list = walker_to_nodes[w] if w in walker_to_nodes else [];
                if node_list {
                    for n in node_list {
                        if n not in real_path {
                            real_path = real_path + [n];
                        }
                    }
                }
            }
            visited = real_path;
            current = str(real_path[len(real_path) - 1]) if len(real_path) > 0 else "";
        } else {
            visited = [];
            current = "";
        }
    }

    async def startReplay -> None;
    async def stepReplay(idx: int, path: list) -> None;
    def nodeColor(node_type: str) -> str;
    def edgeWalkerColor(e0: str, e1: str) -> str;
    def renderEdge(e: dict) -> JsxElement;
    def renderEdgeLabel(e: dict) -> JsxElement;
    def renderEdgeDot(e: dict) -> JsxElement;
    def renderEdgeBeam(e: dict) -> JsxElement;
    def renderNode(n: dict) -> JsxElement;
    def renderTooltip -> JsxElement;
    def renderLastEvent -> JsxElement;

    legend = [
        ("PersonNode", "#FFE500"),
        ("NeedNode", "#4488FF"),
        ("ResourceNode", "#00FF88"),
        ("EligibilityRuleNode", "#FFB344"),
        ("FormNode", "#FF88AA"),
        ("ApplicationNode", "#AA88FF")
    ];

    return
        <div
            style={{
                "background": "rgba(255,255,255,0.03)",
                "backdropFilter": "blur(12px)",
                "border": "0.5px solid rgba(255,255,255,0.08)",
                "borderRadius": "16px",
                "overflow": "hidden"
            }}
        >
            <div
                style={{
                    "padding": "13px 18px",
                    "borderBottom": "0.5px solid rgba(255,255,255,0.06)",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "12px"
                }}
            >
                <div style={{"flex": "1"}}>
                    <div style={{"fontSize": "14px", "fontWeight": "600", "display": "flex", "alignItems": "center", "gap": "8px"}}>
                        Live graph traversal
                        {(len(walker_events) > 0) and <span
                            style={{
                                "fontSize": "10px",
                                "padding": "1px 7px",
                                "borderRadius": "10px",
                                "background": "rgba(0,255,136,0.1)",
                                "color": "#00FF88",
                                "border": "0.5px solid rgba(0,255,136,0.3)",
                                "fontWeight": "500"
                            }}
                        >
                            LIVE · {str(len(visited))}/{str(len(graph_nodes))}
                        </span>}
                    </div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "2px"}}>
                        {((str(len(walker_events)) + " walker events from current session — Replay re-animates the actual traversal.") if (len(walker_events) > 0) else "Send a chat message to populate the graph with real walker activity. Replay shows the demo path until then.")}
                    </div>
                </div>
                <button
                    onClick={lambda _e: MouseEvent { show_why_path = (not show_why_path); }}
                    style={{
                        "padding": "7px 14px",
                        "background": ("rgba(68,136,255,0.15)" if show_why_path else "rgba(255,255,255,0.05)"),
                        "border": ("0.5px solid rgba(68,136,255,0.5)" if show_why_path else "0.5px solid rgba(255,255,255,0.1)"),
                        "borderRadius": "8px",
                        "color": ("#4488FF" if show_why_path else "rgba(255,255,255,0.7)"),
                        "fontSize": "12px",
                        "cursor": "pointer",
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "6px"
                    }}
                >
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none">
                        <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.8"/>
                        <path d="M12 8.5 L 12 13" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"/>
                        <circle cx="12" cy="16" r="0.9" fill="currentColor"/>
                    </svg>
                    {("Hide path labels" if show_why_path else "Why this path?")}
                </button>
                <button
                    onClick={lambda _e: MouseEvent {
                        visited = [];
                        current = "";
                        replay_idx = 0;
                        startReplay();
                    }}
                    style={{
                        "padding": "7px 16px",
                        "background": ("rgba(255,229,0,0.12)" if is_playing else "rgba(255,255,255,0.05)"),
                        "border": ("0.5px solid rgba(255,229,0,0.35)" if is_playing else "0.5px solid rgba(255,255,255,0.1)"),
                        "borderRadius": "8px",
                        "color": ("#FFE500" if is_playing else "#FFFFFF"),
                        "fontSize": "12px",
                        "cursor": "pointer",
                        "display": "flex",
                        "alignItems": "center",
                        "gap": "5px"
                    }}
                >
                    <span className={("replay-spinning" if is_playing else "")}>
                        {("⏸" if is_playing else "▶")}
                    </span>
                    {(" Playing..." if is_playing else " Replay")}
                </button>
            </div>
            <div
                style={{
                    "padding": "9px 18px",
                    "borderBottom": "0.5px solid rgba(255,255,255,0.05)",
                    "display": "flex",
                    "gap": "14px",
                    "flexWrap": "wrap"
                }}
            >
                {[
                    <div
                        key={item[0]}
                        style={{
                            "display": "flex",
                            "alignItems": "center",
                            "gap": "5px",
                            "fontSize": "10px",
                            "color": "rgba(255,255,255,0.4)"
                        }}
                    >
                        <span style={{"width": "7px", "height": "7px", "borderRadius": "50%", "background": item[1], "display": "inline-block"}}/>
                        {item[0]}
                    </div>
                    for item in legend
                ]}
            </div>
            <div style={{"position": "relative"}}>
                <svg
                    width="100%"
                    viewBox="0 0 680 570"
                    style={{"display": "block", "height": "calc(100vh - 240px)", "minHeight": "440px", "maxHeight": "640px"}}
                >
                    {[renderEdge(graph_edges[i]) for i in range(len(graph_edges))]}
                    {[renderEdgeBeam(graph_edges[i]) for i in range(len(graph_edges))]}
                    {[renderEdgeDot(graph_edges[i]) for i in range(len(graph_edges))]}
                    {show_why_path and [renderEdgeLabel(graph_edges[i]) for i in range(len(graph_edges))]}
                    {[renderNode(graph_nodes[i]) for i in range(len(graph_nodes))]}
                </svg>
                {hovered_node and renderTooltip()}
            </div>
            {(len(walker_events) > 0) and renderLastEvent()}
        </div>;
}
