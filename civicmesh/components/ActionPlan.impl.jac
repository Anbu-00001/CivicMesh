"""Async logic for ActionPlan component."""

impl ActionPlan.statusColor(status: str) -> str {
    colors = {
        "approved": "#00FF88",
        "applied": "#4488FF",
        "pending": "#FFB344",
        "denied": "#FF4444"
    };
    return colors.get(status, "rgba(255,255,255,0.25)");
}

impl ActionPlan.statusIcon(status: str) -> str {
    icons = {"approved": "✓", "applied": "✓", "pending": "○", "denied": "✗"};
    return icons.get(status, "○");
}

impl ActionPlan.renderStep(s: Any, i: int) -> JsxElement {
    st = str(s["status"]);
    nm = str(s["name"]);
    sc = statusColor(st);
    card_class = "card-3d card-enter status-" + st;
    dot_class = "status-dot-" + st + ((" step-done") if (st in ["approved","applied"]) else "");
    return
        <div
            key={str(i)}
            className={card_class}
            style={{
                "background": "rgba(255,255,255,0.03)",
                "backdropFilter": "blur(12px)",
                "border": (("0.5px solid " + sc + "35") if (st in ["approved","applied"]) else "0.5px solid rgba(255,255,255,0.07)"),
                "borderRadius": "12px",
                "marginBottom": "9px",
                "overflow": "hidden",
                "opacity": ("0.55" if st == "denied" else "1")
            }}
        >
            <div
                className="card-3d-inner"
                style={{
                    "padding": "13px 15px",
                    "display": "flex",
                    "alignItems": "center",
                    "gap": "12px"
                }}
            >
                <div
                    className={dot_class}
                    style={{
                        "width": "30px",
                        "height": "30px",
                        "borderRadius": "50%",
                        "background": sc + "18",
                        "border": "1px solid " + sc + "55",
                        "display": "flex",
                        "alignItems": "center",
                        "justifyContent": "center",
                        "fontSize": "13px",
                        "color": sc,
                        "flexShrink": "0"
                    }}
                >
                    {statusIcon(st)}
                </div>
                <div style={{"flex": "1"}}>
                    <div style={{"fontSize": "13px", "fontWeight": "500"}}>
                        {nm}
                    </div>
                </div>
                <span
                    style={{
                        "fontSize": "11px",
                        "padding": "3px 9px",
                        "borderRadius": "20px",
                        "background": sc + "18",
                        "color": sc,
                        "border": "0.5px solid " + sc + "40",
                        "fontWeight": "500"
                    }}
                >
                    {st}
                </span>
                {(st == "pending") and <button
                    onClick={lambda _e: MouseEvent { markApplied(nm, i); }}
                    style={{
                        "padding": "5px 11px",
                        "background": "rgba(255,229,0,0.08)",
                        "border": "0.5px solid rgba(255,229,0,0.25)",
                        "borderRadius": "7px",
                        "color": "#FFE500",
                        "fontSize": "11px",
                        "cursor": "pointer"
                    }}
                >
                    Mark applied
                </button>}
            </div>
        </div>;
}

impl ActionPlan.loadPlan -> None {
    loading = True;
    try {
        result = await root spawn MemoryWalker(
            user_id=user_id,
            mode="read_session"
        );
        if result.reports {
            data: Any = result.reports[0];
            all_steps: list = [];
            approved_names: list = [];
            pending_names: list = [];
            denied_names: list = [];
            try { approved_names = list(data["approved"]); } except Exception as _ex { approved_names = []; }
            try { pending_names = list(data["pending"]); } except Exception as _ex { pending_names = []; }
            try { denied_names = list(data["denied"]); } except Exception as _ex { denied_names = []; }
            for name in approved_names {
                all_steps = all_steps + [{"name": name, "status": "approved"}];
                done_count = done_count + 1;
            }
            for name in pending_names {
                all_steps = all_steps + [{"name": name, "status": "pending"}];
            }
            for name in denied_names {
                all_steps = all_steps + [{"name": name, "status": "denied"}];
            }
            steps = all_steps;
        }
    } except Exception as _ex {
        steps = [];
    }
    loading = False;
}

impl ActionPlan.markApplied(resource_name: str, idx: int) -> None {
    try {
        await root spawn MemoryWalker(
            user_id=user_id,
            mode="update_status",
            resource_name=resource_name,
            new_status="applied"
        );
        # Optimistic update
        steps[idx]["status"] = "applied";
        done_count = done_count + 1;
    } except Exception as _ex {}
}
