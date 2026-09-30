"""CivicMesh chat — instant deterministic answers, narrated in the background.

Left: the conversation. Each agent reply is a structured result — the user's
own words highlighted where facts were extracted, explainable match cards
(eligibility, approval odds with a credible interval, per-criterion reasons,
"you'd qualify if…"), an ordered plan, escape routes, one follow-up question
with quick replies, and a latency waterfall of the turn.

Right: what the agent currently knows about the case, and each walker's
real timing from the last turn's trace.
"""
sv import from walkers.intake { IntakeWalker }
sv import from walkers.narrate { NarrateWalker }
sv import from walkers.forget { ForgetWalker }
import from "@jac/runtime" { jacSpawn, jacIsLoggedIn }

# The id of the chat request waiting for an answer (see sendMessage).
glob CM_INFLIGHT: dict = {"id": ""};

# Follow-up questions answered with a quick Yes / No (must live in the .cl.jac:
# globs in .impl.jac files don't reach the client bundle).
glob YES_NO_KEYS: list = ["homeless", "veteran", "disability", "dv", "young_child", "children", "eviction"];

def:pub ChatPane(
    user_id: str,
    on_walker_event: Any,
    auth_ready: Any = None,
    session_data: dict,
    walker_events: list = [],
    platform: Any = None
) -> JsxElement {
    has messages: list[dict] = [],
        input_val: str = "",
        is_loading: bool = False,
        profile_ctx: Any = {},
        pending_question: str = "",
        last_trace: Any = {},
        open_key: str = "",
        waterfall_open: int = -1,
        narr_tick: float = 0.0,
        # Mutated in place by background narration; narr_tick forces a re-render.
        narrations: dict = {},
        # Local offices from HUD / HRSA open data, keyed by bot message id.
        locals: dict = {},
        lang_label: str = "",
        # Reply language picked by the user ("auto" = detect from the message).
        pref_lang: str = "auto",
        # Full-answer translations (LocalizeWalker), keyed by bot message id.
        localized: dict = {},
        # "Delete my data": "" | deleting | done | failed.
        forget_state: str = "",
        # Bot message id whose English original is expanded.
        en_open: str = "",
        # Private session: nothing stays in this browser after the tab closes.
        private_on: bool = False;

    can with entry {
        seed = [{
            "role": "bot",
            "kind": "text",
            "id": "welcome",
            "text": "Hi, I'm CivicMesh. Tell me what's going on, in your own words and in your own language, and I'll find the housing, food, healthcare or legal programs you can use and show exactly why. In 51 languages the whole answer — programs, next steps and my follow-up questions — comes back in yours right away; in 60 more I add a translation a few seconds later, and for languages machines can't translate yet I give you an interpreter card. Pick yours at the top if I get it wrong.",
            "suggestions": [
                "I'm 72, on $1200/month Social Security, my landlord is trying to evict me illegally.",
                "Mi familia y yo no hemos comido en 2 días. Estamos en Texas.",
                "I'm a single mother with 2 kids in Houston. I earn $1,800/month and need housing help.",
                "我今天在哪里可以得到食物？我没有工作。"
            ]
        }];
        has_history_flag = False;
        try { has_history_flag = bool(session_data["has_history"]); } except Exception as _ex {}
        if has_history_flag {
            nxt = "";
            try {
                summary = session_data["session_summary"];
                if summary and summary["next_recommended_step"] { nxt = str(summary["next_recommended_step"]); }
            } except Exception as _ex {}
            if nxt {
                seed = seed + [{"role": "bot", "kind": "text", "id": "memory", "text": "Welcome back. " + nxt, "suggestions": []}];
            }
        }
        messages = seed;
        try {
            saved = localStorage.getItem("cm_lang");
            if saved { pref_lang = saved; }
            if sessionStorage.getItem("cm_private") == "1" { private_on = True; }
        } except Exception as _ex {}
    }

    # Keep the newest turn in view (also when a narration lands).
    can with [messages, narr_tick] entry {
        try {
            thread = document.querySelector(".cm-thread");
            if thread { thread.scrollTop = thread.scrollHeight; }
        } except Exception as _ex {}
    }

    # The input is disabled while a turn runs, which drops keyboard focus to
    # the page. Put it back when the answer lands, so a keyboard or screen-
    # reader user can reply without hunting for the box (not on first load).
    can with [is_loading] entry {
        try {
            if (not is_loading) and len(messages) > 1 and (document.activeElement == document.body or not document.activeElement) {
                box = document.querySelector(".cm-input");
                if box { box.focus(); }
            }
        } except Exception as _ex {}
    }

    async def sendMessage(text_override: str = "", answering: str = "", display: str = "", pin: bool = False) -> None;
    async def safeSpawn(walker_name: str, fields: dict) -> Any;
    async def narrate(msg_id: str, data: Any, user_text: str) -> None;
    async def findLocal(msg_id: str, data: Any) -> None;
    async def localize(msg_id: str, data: Any) -> None;
    def renderInterpreter(card: Any, open_default: bool) -> JsxElement;
    def renderLangPicker -> JsxElement;
    def renderLocal(loc: Any) -> JsxElement;
    def resetCase -> None;
    async def forgetMe -> None;
    def setPrivate(on: bool) -> None;
    def renderPrivacy -> JsxElement;
    def spansToEvents(spans: list) -> list;
    def fmtMs(ms: float) -> str;
    def tierStyle(tier: str, ui: Any) -> dict;
    def L(ui: Any, key: str, fallback: str) -> str;
    def renderRich(text: str) -> JsxElement;
    def renderUserText(text: str, evidence: list) -> JsxElement;
    def renderMessage(msg: dict, idx: int, is_last: bool) -> JsxElement;
    def renderResult(msg: dict, idx: int, is_last: bool) -> JsxElement;
    def renderMatchCard(m: Any, idx: int, j: int, ui: Any) -> JsxElement;
    def renderPlan(plan: Any, ui: Any) -> JsxElement;
    def renderRoute(route: Any, idx: int) -> JsxElement;
    def renderWaterfall(trace: Any, narration: Any, idx: int) -> JsxElement;
    def quickOptions(key: str, es: bool) -> list;
    def renderQuickReplies(q: Any, lang: str, labels: list, q_text: str, affects_text: str) -> JsxElement;
    async def localizeStrings(msg_id: str, data: Any) -> None;
    def renderChip(label: str, payload: str, answering: str) -> JsxElement;
    def renderProfilePanel -> JsxElement;
    def renderPipeline -> JsxElement;

    return
        <div className="cm-chat-grid">
            <div className="cm-panel cm-chat-col">
                <div className="cm-chat-head">
                    <div style={{"flex": "1", "minWidth": "0"}}>
                        <h2 style={{"fontSize": "14px", "fontWeight": "600", "margin": "0"}}>CivicMesh Navigator</h2>
                        <div className="cm-muted" style={{"fontSize": "11px", "marginTop": "2px"}}>
                            Deterministic eligibility engine · 2026 federal rules · 51 machine-drafted languages, 111 selectable · 1 LLM call per turn, off the critical path
                        </div>
                    </div>
                    {is_loading and <div className="cm-badge badge-glow"><span className="cm-dot-live"/>Scoring 40 programs…</div>}
                    {renderLangPicker()}
                    <button className="cm-ghost-btn" onClick={lambda _e: MouseEvent { resetCase(); }} title="Start a new case">New case</button>
                </div>
                <div className="cm-thread" role="log" aria-live="polite" aria-relevant="additions" aria-label="Conversation" aria-busy={is_loading} tabIndex={0}>
                    {[renderMessage(messages[i], i, (i == len(messages) - 1) and (not is_loading)) for i in range(len(messages))]}
                    {is_loading and <div className="cm-row">
                        <div className="cm-avatar">CM</div>
                        <div className="cm-typing" role="status"><span aria-hidden="true"/><span aria-hidden="true"/><span aria-hidden="true"/><span className="cm-sr-only">Working on your answer…</span></div>
                    </div>}
                </div>
                <div className="cm-composer">
                    <input
                        aria-label="Your message"
                        value={input_val}
                        onChange={lambda e: ChangeEvent { input_val = e.target.value; }}
                        onKeyDown={lambda e: KeyboardEvent {
                            if e.key == "Enter" { sendMessage(); }
                        }}
                        placeholder={("Answer the question above, or describe anything else…" if pending_question else "Describe your situation in any language…")}
                        disabled={is_loading}
                        maxLength={4000}
                        className="cm-input"
                    />
                    <button
                        onClick={lambda _e: MouseEvent { sendMessage(); }}
                        disabled={is_loading}
                        className={("cm-send cm-send-on" if (input_val and (not is_loading)) else "cm-send")}
                        aria-label="Send message"
                        title="Send"
                    >
                        →
                    </button>
                </div>
                <p className="cm-safety-line">
                    {"In danger now: "}<a href="tel:911">911</a>
                    {" · Suicide or crisis: call or text "}<a href="tel:988">988</a>
                    {" · Not safe at home: "}<a href="tel:18007997233">1-800-799-7233</a>{" or text START to 88788"}
                </p>
                {renderPrivacy()}
            </div>
            <div className="cm-side" role="region" aria-label="Case file and pipeline" tabIndex={0}>
                {renderProfilePanel()}
                {renderPipeline()}
            </div>
        </div>;
}
