"""Live graph traversal visualization.
Node types match Phase 1 schema exactly.
Replay animates the walker path step by step.
"""

def:pub GraphViz(walker_events: list) -> JsxElement {
    has visited: list[str] = [],
        current: str = "",
        is_playing: bool = False,
        replay_idx: int = 0;

    # Node definitions — match Phase 1 schema exactly
    has graph_nodes: list[dict] = [
        {"id": "root",    "type": "Root",                 "label": "root",      "x": 340, "y": 40},
        {"id": "person",  "type": "PersonNode",            "label": "Person",    "x": 340, "y": 130},
        {"id": "need",    "type": "NeedNode",              "label": "Need",      "x": 340, "y": 220},
        {"id": "r1",      "type": "ResourceNode",          "label": "Section 8", "x": 100, "y": 330},
        {"id": "r2",      "type": "ResourceNode",          "label": "SNAP",      "x": 210, "y": 330},
        {"id": "r3",      "type": "ResourceNode",          "label": "WIC",       "x": 340, "y": 330},
        {"id": "r4",      "type": "ResourceNode",          "label": "LIHEAP",    "x": 460, "y": 330},
        {"id": "r5",      "type": "ResourceNode",          "label": "HCH",       "x": 570, "y": 330},
        {"id": "e1",      "type": "EligibilityRuleNode",   "label": "Rule §8",   "x": 100, "y": 430},
        {"id": "e2",      "type": "EligibilityRuleNode",   "label": "Rule SNAP", "x": 210, "y": 430},
        {"id": "e3",      "type": "EligibilityRuleNode",   "label": "Rule WIC",  "x": 340, "y": 430},
        {"id": "f1",      "type": "FormNode",              "label": "Form §8",   "x": 100, "y": 520},
        {"id": "app1",    "type": "ApplicationNode",       "label": "Applied",   "x": 220, "y": 520},
        {"id": "app2",    "type": "ApplicationNode",       "label": "Pending",   "x": 340, "y": 520}
    ];

    has graph_edges: list[list] = [
        ["root","person"], ["person","need"],
        ["need","r1"], ["need","r2"], ["need","r3"], ["need","r4"], ["need","r5"],
        ["r1","e1"], ["r2","e2"], ["r3","e3"],
        ["e1","f1"], ["person","app1"], ["person","app2"]
    ];

    has walk_path: list[str] = [
        "root","person","need",
        "r1","e1","f1",
        "r2","e2",
        "r3","e3",
        "r4","r5",
        "app1","app2"
    ];

    can with [walker_events] entry {
        if walker_events {
            last: Any = walker_events[len(walker_events) - 1];
            node_id = "";
            try { node_id = str(last["node"]); } except Exception as _ex { node_id = ""; }
            node_map = {
                "root": "root",
                "NeedNode": "need",
                "ActionPlan": "app1",
                "ApplicationNode": "app1"
            };
            mapped = str(node_map.get(node_id, ""));
            if mapped and (mapped not in visited) {
                visited = visited + [mapped];
                current = mapped;
            }
        }
    }

    async def startReplay -> None;
    async def stepReplay -> None;
    def nodeColor(node_type: str) -> str;
    def renderEdge(e: list) -> JsxElement;
    def renderNode(n: dict) -> JsxElement;

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
                    <div style={{"fontSize": "14px", "fontWeight": "600"}}>Live graph traversal</div>
                    <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginTop": "2px"}}>
                        Watch walkers traverse the community resource graph
                    </div>
                </div>
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
            <svg
                width="100%"
                viewBox="0 0 680 570"
                style={{"display": "block", "height": "400px"}}
            >
                {[renderEdge(graph_edges[i]) for i in range(len(graph_edges))]}
                {[renderNode(graph_nodes[i]) for i in range(len(graph_nodes))]}
            </svg>
            {walker_events and <div
                style={{
                    "padding": "8px 18px",
                    "borderTop": "0.5px solid rgba(255,255,255,0.05)",
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.35)",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "6px"
                }}
            >
                <span style={{"color": "#FFE500"}}>
                    {str(walker_events[len(walker_events)-1]["walker"])}
                </span>
                <span>→</span>
                <span>{str(walker_events[len(walker_events)-1]["node"])}</span>
                <span style={{"color": "#00FF88", "marginLeft": "4px"}}>
                    {str(walker_events[len(walker_events)-1]["status"])}
                </span>
            </div>}
        </div>;
}
