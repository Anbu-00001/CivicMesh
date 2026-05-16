"""Return-visit session memory banner.
Only renders when session_data["has_history"] is True.
"""

def:pub SessionBanner(session_data: Any) -> JsxElement {
    has is_visible: bool = True;

    if not is_visible {
        return <div/>;
    }
    if not session_data {
        return <div/>;
    }

    has_hist = False;
    try { has_hist = bool(session_data["has_history"]); } except Exception as _ex { has_hist = False; }
    if not has_hist {
        return <div/>;
    }

    approved: list = [];
    pending: list = [];
    denied: list = [];
    try { approved = list(session_data["approved"]); } except Exception as _ex { approved = []; }
    try { pending = list(session_data["pending"]); } except Exception as _ex { pending = []; }
    try { denied = list(session_data["denied"]); } except Exception as _ex { denied = []; }

    next_step = "";
    try {
        summary_obj: Any = session_data["session_summary"];
        if summary_obj {
            next_step = str(summary_obj["next_recommended_step"]);
        }
    } except Exception as _ex { next_step = ""; }

    return
        <div
            className="banner-slide"
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
