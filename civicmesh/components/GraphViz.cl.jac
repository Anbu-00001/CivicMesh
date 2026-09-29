"""Graph tab — the visitor's real case subgraph, drawn as a decision flow.

Every card and line comes from GraphSnapshotWalker, which reads what the chat
pipeline persisted: PersonNode → latest NeedNode → scored eligible_for edges
(tier + P(eligible)) → ResourceNode → EligibilityRuleNode → FormNode,
ApplicationNodes on applied_to, leads_to routes and SessionInsights.

Read left to right: you and your latest need, the programs the engine scored
for it (ranked), and the programs those lead to later. Encoding rules:
  · color means one thing — the engine's verdict — and never stands alone
    (icon + word; Okabe–Ito-style hues that survive color-vision deficiency);
  · line thickness is P(eligible); arrows are leads_to routes; no dashed lines;
  · rules and forms are the leaves of every program, so they sit inside the
    program card (not as rows of identical dots), and an application is a
    badge on its program (not a line crossing the graph);
  · filled cards were scored for this need, outlined cards are reachable later.
Hover or focus a card to trace its edges; Schema shows node/edge type names;
Replay walks the graph in the order the walkers touched it.
"""

sv import from walkers.graph_snapshot { GraphSnapshotWalker }
import from "@jac/runtime" { jacSpawn }

# Geometry (px). Cards have fixed heights so connector endpoints are known
# without measuring the DOM.
glob GV_PAD: int = 8;
glob GV_HEAD: int = 24;
glob GV_CH: int = 80;
glob GV_GAP: int = 10;
glob GV_YOU_H: int = 58;
glob GV_NEED_H: int = 80;
glob GV_RH: int = 66;
glob GV_LW: int = 196;
glob GV_GL: int = 64;
glob GV_GR: int = 96;
glob GV_RW: int = 188;
glob GV_TIER: dict = {
    "likely": {"color": "#00E08A", "icon": "✓", "label": "Likely"},
    "possible": {"color": "#5AA2FF", "icon": "~", "label": "Possible"},
    "needs_info": {"color": "#FFB344", "icon": "?", "label": "Needs info"},
    "unlikely": {"color": "rgba(255,255,255,0.62)", "icon": "✕", "label": "Unlikely"}
};
glob GV_TIER_ORDER: list = ["likely", "possible", "needs_info", "unlikely"];
# Automatic retries after a failed load (a flaky hosting proxy).
glob GV_RETRY: dict = {"n": 0};

def:pub GraphViz(walker_events: list, user_id: str = "") -> JsxElement {
    has snap: Any = None,
        loading: bool = False,
        err: str = "",
        selected: str = "",
        hovered: str = "",
        schema: bool = False,
        playing: bool = False,
        visited: list = [],
        current: str = "";

    can with [walker_events] entry {
        loadSnap();
    }

    async def loadSnap -> None;
    def model -> dict;
    def replayOrder -> list;
    def startReplay -> None;
    def stepReplay(idx: int, order: list) -> None;
    def isOn(nid: str) -> bool;
    def pick(nid: str) -> None;
    def renderLeft(m: dict) -> JsxElement;
    def renderCard(n: Any, i: int, m: dict) -> JsxElement;
    def renderRight(m: dict) -> JsxElement;
    def renderFan(m: dict) -> JsxElement;
    def renderRoutes(m: dict) -> JsxElement;
    def renderDetail(m: dict) -> JsxElement;
    def renderLegend -> JsxElement;

    nodes: list = list(snap["nodes"]) if (snap and snap["nodes"]) else [];
    counts: Any = snap["counts"] if (snap and snap["counts"]) else {};
    empty = (not snap) or bool(snap["empty"]) or len(nodes) <= 2;
    m = model();
    has_routes = len(m["routes"]) > 0;
    gr = GV_GR if has_routes else (64 if len(m["arcs"]) > 0 else 12);
    cols = str(GV_LW) + "px " + str(GV_GL) + "px minmax(220px, 1fr) " + str(gr) + "px" + ((" " + str(GV_RW) + "px") if has_routes else "");

    return
        <div className="cm-panel gv-wrap">
            <div className="gv-head">
                <div className="gv-head-text">
                    <div className="gv-title">Your case graph</div>
                    <div className="cm-muted gv-sub">
                        {("Read live from your graph: every card is a node a walker wrote during your chat. Left to right — your need, the programs the engine scored for it, and where they lead. Hover or tap a card to trace its edges.") if (not empty) else ("Send a message in Chat — each turn writes a NeedNode and one scored eligible_for edge per matched program, and they appear here.")}
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
                    <button className={"cm-ghost-btn" + (" gv-btn-on" if schema else "")} aria-pressed={("true" if schema else "false")} onClick={lambda _e: MouseEvent { schema = not schema; }} title="Show the graph schema: node and edge type names">Schema</button>
                    <button className="cm-ghost-btn" onClick={lambda _e: MouseEvent { loadSnap(); }} disabled={loading}>{("Loading…" if loading else "Refresh")}</button>
                    <button className={"cm-ghost-btn" + (" gv-btn-on" if playing else "")} onClick={lambda _e: MouseEvent { startReplay(); }} disabled={empty or playing}>{("Replaying…" if playing else "▶ Replay turn")}</button>
                </div>
            </div>
            {err and <div className="gv-err"><span>{"Couldn't load the graph. " + err}</span><button className="cm-ghost-btn" onClick={lambda _e: MouseEvent { GV_RETRY["n"] = 0; loadSnap(); }} disabled={loading}>{("Loading…" if loading else "Try again")}</button></div>}
            <div className="gv-body">
                <div className="gv-canvas">
                    {empty and <div className="gv-empty">
                        <div className="gv-empty-flow"><span>You</span><i/><span>Need</span><i/><span>Programs</span><i/><span>Routes</span></div>
                        <div className="cm-muted">Nothing here yet — your graph starts with your first message.</div>
                    </div>}
                    {(not empty) and <div className="gv-flow" style={{"gridTemplateColumns": cols}}>
                        {renderLeft(m)}
                        <div className="gv-gcol">{renderFan(m)}</div>
                        <div className="gv-col gv-col-mid">
                            <div className="gv-colhead">{"2 · Programs scored for this need"}</div>
                            <div className="gv-stack">
                                {[renderCard(m["progs"][i], i, m) for i in range(len(m["progs"]))]}
                                {len(m["progs"]) == 0 and <div className="gv-none cm-muted">No program matched this need yet — answer the follow-up question in Chat.</div>}
                            </div>
                        </div>
                        <div className="gv-gcol">{renderRoutes(m)}</div>
                        {has_routes and renderRight(m)}
                    </div>}
                </div>
                <div className="gv-side">
                    {renderDetail(m)}
                    {renderLegend()}
                </div>
            </div>
        </div>;
}
