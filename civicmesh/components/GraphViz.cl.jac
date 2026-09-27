"""Graph tab — the visitor's real case subgraph, not a drawing.

Every node and edge comes from GraphSnapshotWalker, which reads what the
chat pipeline persisted: PersonNode → latest NeedNode → scored eligible_for
edges (tier + P(eligible)) → ResourceNode → EligibilityRuleNode → FormNode,
ApplicationNodes on applied_to, leads_to escape routes and SessionInsights.
Layout is layered by node type; Replay walks the graph in the order the
walkers touched it (Intake → Eligibility → Navigation → Pathfinder).
"""

sv import from walkers.graph_snapshot { GraphSnapshotWalker }
import from "@jac/runtime" { jacSpawn }

glob GV_W: int = 760;
glob GV_H: int = 540;
glob GV_ROW_Y: dict = {"Root": 34, "PersonNode": 104, "NeedNode": 184, "ApplicationNode": 184, "SessionInsight": 184, "ResourceNode": 300, "EligibilityRuleNode": 396, "FormNode": 480};
glob GV_COLORS: dict = {"Root": "#9AA0A6", "PersonNode": "#FFE500", "NeedNode": "#4488FF", "ResourceNode": "#00E08A", "EligibilityRuleNode": "#FFB344", "FormNode": "#FF88AA", "ApplicationNode": "#AA88FF", "SessionInsight": "#00C8FF"};
glob GV_TIER: dict = {"likely": "#00E08A", "possible": "#5AA2FF", "needs_info": "#FFB344", "unlikely": "rgba(255,255,255,0.35)"};
glob GV_LEGEND: list = [["PersonNode", "You"], ["NeedNode", "Need"], ["ResourceNode", "Program"], ["EligibilityRuleNode", "Rule"], ["FormNode", "Form"], ["ApplicationNode", "Application"], ["SessionInsight", "Self-critique"]];

def:pub GraphViz(walker_events: list, user_id: str = "") -> JsxElement {
    has snap: Any = None,
        loading: bool = False,
        err: str = "",
        selected: str = "",
        hovered: str = "",
        show_labels: bool = False,
        playing: bool = False,
        visited: list = [],
        current: str = "";

    can with [walker_events] entry {
        loadSnap();
    }

    async def loadSnap -> None;
    def layout -> dict;
    def replayOrder -> list;
    def startReplay -> None;
    def stepReplay(idx: int, order: list) -> None;
    def renderEdge(e: Any, pos: Any, i: int) -> JsxElement;
    def renderNode(n: Any, pos: Any) -> JsxElement;
    def renderDetail(pos: Any) -> JsxElement;

    nodes: list = list(snap["nodes"]) if (snap and snap["nodes"]) else [];
    edges: list = list(snap["edges"]) if (snap and snap["edges"]) else [];
    counts: Any = snap["counts"] if (snap and snap["counts"]) else {};
    pos = layout();
    empty = (not snap) or bool(snap["empty"]) or len(nodes) <= 2;

    return
        <div className="cm-panel gv-wrap">
            <div className="gv-head">
                <div style={{"flex": "1", "minWidth": "0"}}>
                    <div className="gv-title">Your case graph</div>
                    <div className="cm-muted gv-sub">
                        {("Read live from your graph: every node below was written by a walker during your chat. Hover or tap a node for its fields.") if (not empty) else ("Send a message in Chat — each turn writes a NeedNode and one scored eligible_for edge per matched program, and they appear here.")}
                    </div>
                    {(not empty) and <div className="gv-counts">
                        <span className="cm-fact">{str(counts["NeedNode"]) + " need" + ("" if Number(counts["NeedNode"]) == 1 else "s")}</span>
                        <span className="cm-fact">{str(counts["eligible_for"]) + " eligible_for edges (latest need)"}</span>
                        <span className="cm-fact">{str(counts["ApplicationNode"]) + " open application" + ("" if Number(counts["ApplicationNode"]) == 1 else "s")}</span>
                        <span className="cm-fact">{str(counts["ResourceNode"]) + " programs in graph"}</span>
                        {Number(counts["SessionInsight"]) > 0 and <span className="cm-fact">{str(counts["SessionInsight"]) + " self-critiques"}</span>}
                    </div>}
                </div>
                <div className="gv-actions">
                    <button className="cm-ghost-btn" onClick={lambda _e: MouseEvent { show_labels = not show_labels; }}>{("Hide edge labels" if show_labels else "Edge labels")}</button>
                    <button className="cm-ghost-btn" onClick={lambda _e: MouseEvent { loadSnap(); }} disabled={loading}>{("Loading…" if loading else "Refresh")}</button>
                    <button className={"cm-ghost-btn" + (" gv-btn-on" if playing else "")} onClick={lambda _e: MouseEvent { startReplay(); }} disabled={empty or playing}>{("Replaying…" if playing else "▶ Replay turn")}</button>
                </div>
            </div>
            {err and <div className="gv-err">{"Couldn't load the graph: " + err}</div>}
            <div className="gv-body">
                <div className="gv-canvas">
                    <svg viewBox={"0 0 " + str(GV_W) + " " + str(GV_H)} preserveAspectRatio="xMidYMid meet" className="gv-svg" role="img" aria-label="Case graph">
                        {[renderEdge(edges[i], pos, i) for i in range(len(edges))]}
                        {[renderNode(nodes[i], pos) for i in range(len(nodes))]}
                    </svg>
                </div>
                <div className="gv-side">
                    {renderDetail(pos)}
                    <div className="gv-legend">
                        {[<div key={l[0]} className="gv-legend-row"><span className="gv-dot" style={{"background": GV_COLORS[l[0]]}}/><span>{l[1]}</span><span className="cm-muted gv-legend-type">{l[0]}</span></div> for l in GV_LEGEND]}
                        <div className="gv-legend-row"><span className="gv-ring" style={{"borderColor": GV_TIER["likely"]}}/><span>likely</span><span className="gv-ring" style={{"borderColor": GV_TIER["needs_info"]}}/><span>needs info</span></div>
                        <div className="gv-legend-row"><span className="gv-dash"/><span>leads_to route</span></div>
                    </div>
                </div>
            </div>
        </div>;
}
