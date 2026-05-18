"""Impl helpers + ImpactWalker spawn for ImpactReport."""

impl ImpactReport.loadImpact -> None {
    loading = True;
    err = "";
    try {
        result = await root spawn ImpactWalker();
        # `result.reports` is an array; in JS, an empty array `[]` is truthy,
        # so `if result.reports` alone would pass even with no data and crash
        # on `[0]`. Length-guard explicitly.
        reports = result.reports if result.reports else [];
        if len(reports) > 0 {
            data: Any = reports[0];
            summary = data;
        } else {
            summary = None;
        }
    } except Exception as e {
        # We deliberately keep the error opaque so a stale walker name
        # mismatch shows up but we don't dump a stack trace to the user.
        err = "ImpactWalker failed";
    }
    loading = False;
}

impl ImpactReport.renderStatCard(label: str, value: str, sub: str, color: str) -> JsxElement {
    return
        <div
            key={label}
            style={{
                "padding": "16px 18px",
                "background": "rgba(255,255,255,0.03)",
                "backdropFilter": "blur(12px)",
                "border": "0.5px solid " + color + "30",
                "borderTop": "2px solid " + color,
                "borderRadius": "12px"
            }}
        >
            <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.5)", "textTransform": "uppercase", "letterSpacing": "0.06em", "fontWeight": "500"}}>
                {label}
            </div>
            <div style={{"fontSize": "28px", "fontWeight": "700", "letterSpacing": "-0.03em", "color": color, "lineHeight": "1.1", "marginTop": "4px"}}>
                {value}
            </div>
            <div style={{"fontSize": "10px", "color": "rgba(255,255,255,0.35)", "marginTop": "5px"}}>
                {sub}
            </div>
        </div>;
}

impl ImpactReport.renderCategoryBar(cat: str, count: int, max_count: int, color: str) -> JsxElement {
    pct = int((count * 100) / max_count) if max_count > 0 else 0;
    # Capitalize the leading character without an LLM trip — Jac doesn't
    # ship a .capitalize() helper on str literals here, so we do it manually.
    label = cat;
    if cat {
        first_c = cat[0];
        rest = cat[1:];
        label = first_c.upper() + rest;
    }
    return
        <div
            key={cat}
            style={{"marginBottom": "10px"}}
        >
            <div style={{"display": "flex", "justifyContent": "space-between", "marginBottom": "4px"}}>
                <span style={{"fontSize": "12px", "color": "rgba(255,255,255,0.7)", "fontWeight": "500"}}>
                    {label}
                </span>
                <span style={{"fontSize": "12px", "color": color, "fontWeight": "600", "fontFamily": "ui-monospace, monospace"}}>
                    {str(count)}
                </span>
            </div>
            <div style={{"height": "6px", "background": "rgba(255,255,255,0.05)", "borderRadius": "3px", "overflow": "hidden"}}>
                <div
                    style={{
                        "height": "100%",
                        "width": str(pct) + "%",
                        "background": color,
                        "borderRadius": "3px",
                        "transition": "width 0.6s ease"
                    }}
                />
            </div>
        </div>;
}

impl ImpactReport.renderResourceBar(name: str, count: int, max_count: int) -> JsxElement {
    pct = int((count * 100) / max_count) if max_count > 0 else 0;
    return
        <div
            key={name}
            style={{"marginBottom": "9px"}}
        >
            <div style={{"display": "flex", "justifyContent": "space-between", "marginBottom": "3px"}}>
                <span style={{"fontSize": "12px", "color": "rgba(255,255,255,0.75)"}}>
                    {name}
                </span>
                <span style={{"fontSize": "11px", "color": "#FFE500", "fontFamily": "ui-monospace, monospace"}}>
                    {str(count) + (" application" if count == 1 else " applications")}
                </span>
            </div>
            <div style={{"height": "5px", "background": "rgba(255,255,255,0.05)", "borderRadius": "3px", "overflow": "hidden"}}>
                <div
                    style={{
                        "height": "100%",
                        "width": str(pct) + "%",
                        "background": "linear-gradient(90deg, #FFE500, #FFB344)",
                        "borderRadius": "3px",
                        "transition": "width 0.6s ease"
                    }}
                />
            </div>
        </div>;
}

impl ImpactReport.renderLanguageChip(lang: str, count: int) -> JsxElement {
    return
        <div
            key={lang}
            style={{
                "padding": "6px 12px",
                "background": "rgba(68,136,255,0.08)",
                "border": "0.5px solid rgba(68,136,255,0.3)",
                "borderRadius": "999px",
                "fontSize": "11px",
                "color": "rgba(255,255,255,0.85)",
                "display": "flex",
                "alignItems": "center",
                "gap": "6px"
            }}
        >
            <span style={{"color": "#4488FF", "fontWeight": "700", "letterSpacing": "0.05em", "textTransform": "uppercase"}}>
                {lang}
            </span>
            <span style={{"color": "rgba(255,255,255,0.5)", "fontSize": "10px"}}>
                {"· " + str(count)}
            </span>
        </div>;
}

impl ImpactReport.renderTopNeedCard(cat_lookup: Any) -> JsxElement {
    # Data-driven replacement for the previous hardcoded "Maria" persona
    # quote. We receive the cat_count_by_key lookup from the component body
    # (impls can't reach body locals directly, only `has` state) and pick
    # the highest count. If no data yet, fall back to a quiet hint pointing
    # the user back to the Chat tab so the card never sits empty.
    top_cat = "";
    top_n = 0;
    cat_order: list = ["housing", "food", "healthcare", "legal"];
    for k in cat_order {
        if k in cat_lookup {
            v = int(cat_lookup[k]);
            if v > top_n {
                top_n = v;
                top_cat = k;
            }
        }
    }
    # Capitalize first letter manually — Jac doesn't expose a built-in here.
    top_cat_label = top_cat;
    if top_cat {
        top_cat_label = top_cat[0].upper() + top_cat[1:];
    }
    return
        <div style={{"display": "flex", "flexDirection": "column"}}>
            <div style={{"fontSize": "10px", "color": "rgba(255,229,0,0.85)", "textTransform": "uppercase", "letterSpacing": "0.06em", "marginBottom": "10px"}}>
                Most-asked need this session
            </div>
            {(top_n > 0) and <div>
                <div style={{"display": "flex", "alignItems": "baseline", "gap": "12px"}}>
                    <span style={{"fontSize": "32px", "fontWeight": "800", "letterSpacing": "-0.03em", "color": "#FFE500"}}>
                        {top_cat_label}
                    </span>
                    <span style={{"fontSize": "16px", "fontWeight": "600", "color": "rgba(255,255,255,0.5)"}}>
                        {str(top_n) + " NeedNode" + ("s" if top_n != 1 else "")}
                    </span>
                </div>
                <div style={{"fontSize": "11px", "color": "rgba(255,255,255,0.45)", "marginTop": "10px", "lineHeight": "1.55"}}>
                    Aggregated live from NeedNode.category across every PersonNode in the graph. ImpactWalker reads each PersonNode → has_need → NeedNode chain on every dashboard mount.
                </div>
            </div>}
            {(top_n == 0) and <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.4)", "fontStyle": "italic", "lineHeight": "1.5"}}>
                No NeedNodes yet — send a prompt in the Chat tab and IntakeWalker will write the first one. This card updates live.
            </div>}
        </div>;
}
