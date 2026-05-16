"""Return-visit session memory banner.
Only renders when session_data.has_history is True.
"""

def:pub SessionBanner(session_data: dict) -> JsxElement {
    has is_visible: bool = True;

    if not is_visible {
        return <div/>;
    }
    if not session_data.get("has_history", False) {
        return <div/>;
    }

    approved = list(session_data.get("approved", []) or []);
    pending = list(session_data.get("pending", []) or []);
    denied = list(session_data.get("denied", []) or []);
    summary_obj = session_data.get("session_summary", None);
    next_step = str(dict(summary_obj).get("next_recommended_step", "")) if summary_obj else "";

    return
        <div
            style={{
                "margin": "0 0 16px 0",
                "padding": "12px 16px",
                "background": "rgba(255,229,0,0.05)",
                "border": "0.5px solid rgba(255,229,0,0.18)",
                "borderRadius": "12px",
                "display": "flex",
                "alignItems": "center",
                "gap": "12px"
            }}
        >
            <span style={{"fontSize": "20px"}}>👋</span>
            <div style={{"flex": "1"}}>
                <div style={{"fontSize": "13px", "fontWeight": "600", "color": "#FFE500"}}>
                    Welcome back
                </div>
                <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.55)", "marginTop": "2px"}}>
                    {(next_step if next_step else (str(len(approved)) + " approved · " + str(len(pending)) + " pending · " + str(len(denied)) + " denied"))}
                </div>
            </div>
            <div style={{"display": "flex", "gap": "8px"}}>
                {(len(approved) > 0) and <div style={{"textAlign": "center"}}>
                    <div style={{"fontSize": "16px", "fontWeight": "600", "color": "#00FF88"}}>
                        {str(len(approved))}
                    </div>
                    <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)"}}>
                        Approved
                    </div>
                </div>}
                {(len(pending) > 0) and <div style={{"textAlign": "center"}}>
                    <div style={{"fontSize": "16px", "fontWeight": "600", "color": "#FFB344"}}>
                        {str(len(pending))}
                    </div>
                    <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)"}}>
                        Pending
                    </div>
                </div>}
            </div>
            <button
                onClick={lambda _e: MouseEvent { is_visible = False; }}
                style={{
                    "background": "transparent",
                    "border": "none",
                    "color": "rgba(255,255,255,0.25)",
                    "cursor": "pointer",
                    "fontSize": "18px",
                    "lineHeight": "1",
                    "padding": "4px"
                }}
            >
                ×
            </button>
        </div>;
}
