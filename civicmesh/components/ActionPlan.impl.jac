"""Async logic for ActionPlan component."""

impl ActionPlan.renderSessionContext -> JsxElement {
    # Session-context side panel shown next to the empty-state cards.
    # Surfaces walker activity counts and a quick-nav to other tabs so the
    # column on the right doesn't sit empty on wide screens.
    walker_rows: list[dict] = [
        {"name": "IntakeWalker",      "color": "#FFE500", "count": intake_n},
        {"name": "EligibilityWalker", "color": "#4488FF", "count": elig_n},
        {"name": "NavigationWalker",  "color": "#00FF88", "count": nav_n},
        {"name": "MemoryWalker",      "color": "#FFB344", "count": mem_n},
        {"name": "EscalationWalker",  "color": "#FF4444", "count": esc_n}
    ];
    return
        <div style={{"display": "flex", "flexDirection": "column", "gap": "12px"}}>
            <div
                style={{
                    "padding": "14px",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "14px"
                }}
            >
                <div style={{
                    "fontSize": "10px",
                    "color": "rgba(255,255,255,0.35)",
                    "textTransform": "uppercase",
                    "letterSpacing": "0.06em",
                    "marginBottom": "10px"
                }}>
                    Session activity
                </div>
                {[renderWalkerRow(walker_rows[ri]) for ri in range(len(walker_rows))]}
                <div style={{
                    "marginTop": "10px",
                    "paddingTop": "10px",
                    "borderTop": "0.5px solid rgba(255,255,255,0.06)",
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.45)"
                }}>
                    {str(len(walker_events)) + " events captured this session"}
                </div>
            </div>
            <div
                style={{
                    "padding": "14px",
                    "background": "rgba(255,255,255,0.03)",
                    "backdropFilter": "blur(12px)",
                    "border": "0.5px solid rgba(255,255,255,0.08)",
                    "borderRadius": "14px"
                }}
            >
                <div style={{
                    "fontSize": "10px",
                    "color": "rgba(255,255,255,0.35)",
                    "textTransform": "uppercase",
                    "letterSpacing": "0.06em",
                    "marginBottom": "10px"
                }}>
                    Where to next
                </div>
                <div style={{"display": "flex", "flexDirection": "column", "gap": "8px", "fontSize": "12px", "color": "rgba(255,255,255,0.7)", "lineHeight": "1.5"}}>
                    <div>
                        <strong style={{"color": "#FFE500"}}>Chat</strong> — start or continue a session with the multi-agent pipeline.
                    </div>
                    <div>
                        <strong style={{"color": "#FFE500"}}>Graph</strong> — watch the real walker traversal across PersonNode / ResourceNode / FormNode.
                    </div>
                    <div>
                        <strong style={{"color": "#FFE500"}}>Telemetry</strong> — see live per-walker event counts and the call tree.
                    </div>
                </div>
            </div>
        </div>;
}

impl ActionPlan.renderWalkerRow(w: dict) -> JsxElement {
    name = str(w["name"]);
    color = str(w["color"]);
    count = int(w["count"]);
    is_active = count > 0;
    return
        <div
            key={name}
            style={{
                "display": "flex",
                "alignItems": "center",
                "gap": "8px",
                "padding": "5px 0",
                "borderBottom": "0.5px solid rgba(255,255,255,0.04)"
            }}
        >
            <span style={{
                "width": "8px",
                "height": "8px",
                "borderRadius": "50%",
                "background": (color if is_active else "rgba(255,255,255,0.15)"),
                "display": "inline-block",
                "flexShrink": "0"
            }}/>
            <span
                style={{
                    "fontSize": "12px",
                    "color": (color if is_active else "rgba(255,255,255,0.3)"),
                    "fontWeight": ("600" if is_active else "400"),
                    "flex": "1"
                }}
            >
                {name}
            </span>
            <span
                style={{
                    "fontSize": "11px",
                    "color": (color if is_active else "rgba(255,255,255,0.25)"),
                    "fontFamily": "ui-monospace, monospace"
                }}
            >
                {str(count)}
            </span>
        </div>;
}


impl ActionPlan.statusColor(status: str) -> str {
    colors = {
        "approved": "#00FF88",
        "applied": "#4488FF",
        "pending": "#FFB344",
        "denied": "#FF4444"
    };
    return colors.get(status, "rgba(255,255,255,0.25)");
}

impl ActionPlan.statusIcon(status: str, color: str) -> JsxElement {
    # Inline SVG status glyphs replace the previous emoji circles (✓ ○ ✗).
    # Each shape is traced from the center of a 24-unit viewBox so it scales
    # cleanly with the surrounding bubble's width.
    if status == "approved" or status == "applied" {
        # Filled checkmark circle
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="10" fill={color} opacity="0.18"/>
                <path
                    d="M7 12.5 L 11 16.5 L 17 8.5"
                    stroke={color}
                    strokeWidth="2.2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                />
            </svg>;
    }
    if status == "pending" {
        # Clock outline — denotes "in progress / awaiting response"
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="9" stroke={color} strokeWidth="1.8"/>
                <path
                    d="M12 7.5 L 12 12 L 15.5 14"
                    stroke={color}
                    strokeWidth="1.8"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                />
            </svg>;
    }
    if status == "denied" {
        # X inside a circle
        return
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="9" stroke={color} strokeWidth="1.8"/>
                <path
                    d="M9 9 L 15 15 M 15 9 L 9 15"
                    stroke={color}
                    strokeWidth="2"
                    strokeLinecap="round"
                />
            </svg>;
    }
    # Default: hollow circle
    return
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="12" r="9" stroke={color} strokeWidth="1.8"/>
        </svg>;
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
                        "color": sc,
                        "flexShrink": "0"
                    }}
                >
                    {statusIcon(st, sc)}
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
                {(st == "pending" or st == "applied") and <button
                    onClick={lambda _e: MouseEvent { markOutcome(nm, i, "approved"); }}
                    title="Record the real outcome — updates this program's Beta approval posterior"
                    style={{"padding": "5px 9px", "background": "rgba(0,224,138,0.08)", "border": "0.5px solid rgba(0,224,138,0.3)", "borderRadius": "7px", "color": "#00E08A", "fontSize": "11px", "cursor": "pointer"}}
                >
                    Approved
                </button>}
                {(st == "pending" or st == "applied") and <button
                    onClick={lambda _e: MouseEvent { markOutcome(nm, i, "denied"); }}
                    title="Record the real outcome — updates this program's Beta approval posterior"
                    style={{"padding": "5px 9px", "background": "rgba(255,107,107,0.08)", "border": "0.5px solid rgba(255,107,107,0.3)", "borderRadius": "7px", "color": "#FF6B6B", "fontSize": "11px", "cursor": "pointer"}}
                >
                    Denied
                </button>}
            </div>
        </div>;
}

impl ActionPlan.loadPlan -> None {
    loading = True;
    res = await jacSpawn("MemoryWalker", "", {"user_id": user_id, "mode": "read_session"}).catch(lambda e: Any -> dict { return {"reports": [], "spawn_error": str(e)}; });
    try {
        if res["reports"] and len(res["reports"]) > 0 {
            data: Any = res["reports"][0];
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
    res = await jacSpawn("MemoryWalker", "", {"user_id": user_id, "mode": "update_status", "resource_name": resource_name, "new_status": "applied"}).catch(lambda e: Any -> dict { return {"reports": [], "spawn_error": str(e)}; });
    if not res["spawn_error"] {
        steps[idx]["status"] = "applied";
        done_count = done_count + 1;
    }
}

impl ActionPlan.markOutcome(resource_name: str, idx: int, outcome: str) -> None {
    res = await jacSpawn("MemoryWalker", "", {
        "user_id": user_id,
        "mode": "update_status",
        "resource_name": resource_name,
        "new_status": outcome,
        "denial_reason": ("Application denied" if outcome == "denied" else "")
    }).catch(lambda err: Any -> dict { return {"reports": []}; });
    reps = res["reports"];
    if reps and len(reps) > 0 {
        r = reps[len(reps) - 1];
        post = r["posterior"] if r else None;
        if post and post["mean"] != None {
            outcome_note = "Recorded: " + resource_name + " " + outcome + ". Approval odds " + str(Math.round(Number(post["before"]) * 100)) + "% → " + str(Math.round(Number(post["mean"]) * 100)) + "% (Beta posterior, " + str(post["observed"]) + " real outcome" + ("s" if post["observed"] != 1 else "") + "). Future rankings use it.";
        } else {
            outcome_note = "Recorded: " + resource_name + " " + outcome + ".";
        }
    }
    steps[idx]["status"] = outcome;
    steps = list(steps);
}
