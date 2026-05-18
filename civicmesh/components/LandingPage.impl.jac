"""Render helpers for LandingPage."""

impl LandingPage.renderPersonaPill(label: str, color: str) -> JsxElement {
    return
        <div
            key={label}
            className="lp-persona"
            style={{
                "padding": "7px 14px",
                "background": color + "10",
                "border": "0.5px solid " + color + "40",
                "color": color,
                "borderRadius": "999px",
                "fontSize": "12px",
                "fontWeight": "500",
                "letterSpacing": "0.005em",
                "cursor": "default"
            }}
        >
            {label}
        </div>;
}

impl LandingPage.renderStatTile(value: str, label: str, sub: str, accent: str) -> JsxElement {
    return
        <div
            key={label}
            className="lp-glass lp-stat"
            style={{
                "padding": "22px 20px",
                "position": "relative",
                "overflow": "hidden",
                "borderTop": "2px solid " + accent
            }}
        >
            <div
                className="lp-orb"
                style={{
                    "width": "140px",
                    "height": "140px",
                    "background": accent,
                    "top": "-50px",
                    "right": "-40px",
                    "opacity": "0.18"
                }}
            />
            <div style={{
                "fontSize": "44px",
                "fontWeight": "800",
                "letterSpacing": "-0.04em",
                "color": accent,
                "lineHeight": "1",
                "position": "relative",
                "zIndex": "1"
            }}>
                {value}
            </div>
            <div style={{
                "fontSize": "12px",
                "color": "rgba(255,255,255,0.7)",
                "marginTop": "10px",
                "fontWeight": "600",
                "letterSpacing": "0.01em",
                "position": "relative",
                "zIndex": "1"
            }}>
                {label}
            </div>
            <div style={{
                "fontSize": "10.5px",
                "color": "rgba(255,255,255,0.4)",
                "marginTop": "4px",
                "lineHeight": "1.45",
                "position": "relative",
                "zIndex": "1"
            }}>
                {sub}
            </div>
        </div>;
}

impl LandingPage.renderWalkerCard(idx: int, name: str, role: str, color: str, tilt: str) -> JsxElement {
    # `tilt` is passed as a CSS rotateY angle string ("-3deg", "2deg", ...).
    # The cards alternate left/right tilt so the row reads like a fanned
    # deck of cards rather than a tidy row of buttons. Hover undoes the
    # tilt and lifts the card; see .lp-walker-card in index.css.
    return
        <div
            key={name}
            className="lp-glass lp-walker-card"
            style={{
                "--tilt": tilt,
                "padding": "20px 18px",
                "display": "flex",
                "flexDirection": "column",
                "gap": "10px",
                "minHeight": "180px",
                "borderTop": "2px solid " + color,
                "boxShadow":
                    "inset 0 1px 0 0 rgba(255,255,255,0.08), "
                    + "0 18px 36px -16px " + color + "30"
            }}
        >
            <div style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between"}}>
                <div style={{
                    "width": "26px",
                    "height": "26px",
                    "borderRadius": "8px",
                    "background": color + "20",
                    "border": "1px solid " + color + "60",
                    "color": color,
                    "fontSize": "12px",
                    "fontWeight": "700",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "center",
                    "flexShrink": "0",
                    "fontFamily": "ui-monospace, monospace"
                }}>
                    {str(idx)}
                </div>
                <div style={{
                    "width": "8px",
                    "height": "8px",
                    "borderRadius": "50%",
                    "background": color,
                    "boxShadow": "0 0 8px " + color
                }}/>
            </div>
            <div style={{
                "fontSize": "16px",
                "fontWeight": "700",
                "color": color,
                "letterSpacing": "-0.01em",
                "marginTop": "4px"
            }}>
                {name}
            </div>
            <div style={{
                "fontSize": "10px",
                "color": "rgba(255,255,255,0.4)",
                "textTransform": "uppercase",
                "letterSpacing": "0.08em",
                "fontWeight": "600"
            }}>
                Walker
            </div>
            <div style={{
                "fontSize": "12px",
                "color": "rgba(255,255,255,0.62)",
                "lineHeight": "1.5",
                "marginTop": "4px"
            }}>
                {role}
            </div>
        </div>;
}

impl LandingPage.renderTrackBadge(label: str, accent: str) -> JsxElement {
    return
        <div
            key={label}
            style={{
                "padding": "11px 16px",
                "background": "linear-gradient(135deg, " + accent + "18 0%, " + accent + "08 100%)",
                "border": "0.5px solid " + accent + "55",
                "color": accent,
                "borderRadius": "12px",
                "fontSize": "13px",
                "fontWeight": "600",
                "letterSpacing": "0.005em",
                "display": "flex",
                "alignItems": "center",
                "gap": "10px",
                "boxShadow": "inset 0 1px 0 rgba(255,255,255,0.05), 0 6px 14px -8px " + accent + "40"
            }}
        >
            <span style={{
                "width": "6px",
                "height": "6px",
                "borderRadius": "50%",
                "background": accent,
                "boxShadow": "0 0 6px " + accent
            }}/>
            {label}
        </div>;
}

impl LandingPage.renderPreviewBubble(role: str, walker_name: str, text: str, color: str) -> JsxElement {
    # Mock chat bubbles rendered inside the hero's "live session" glass
    # card. Pure decoration — no walker spawns happen from this page.
    is_user = role == "user";
    return
        <div
            key={text}
            style={{
                "display": "flex",
                "alignItems": "flex-start",
                "gap": "10px",
                "justifyContent": ("flex-end" if is_user else "flex-start")
            }}
        >
            {(not is_user) and <div style={{
                "width": "24px",
                "height": "24px",
                "borderRadius": "50%",
                "background": color,
                "display": "flex",
                "alignItems": "center",
                "justifyContent": "center",
                "fontSize": "9px",
                "fontWeight": "800",
                "color": "#0A0A0A",
                "flexShrink": "0",
                "marginTop": "1px",
                "boxShadow": "0 4px 10px -2px " + color + "60"
            }}>
                CM
            </div>}
            <div style={{"maxWidth": "82%"}}>
                {((not is_user) and walker_name) and <div style={{
                    "fontSize": "9px",
                    "color": color,
                    "marginBottom": "3px",
                    "fontWeight": "600",
                    "letterSpacing": "0.04em",
                    "textTransform": "uppercase",
                    "fontFamily": "ui-monospace, monospace"
                }}>
                    {walker_name}
                </div>}
                <div style={{
                    "padding": "9px 13px",
                    "borderRadius": ("14px 14px 4px 14px" if is_user else "4px 14px 14px 14px"),
                    "background": ("rgba(255,229,0,0.95)" if is_user else "rgba(255,255,255,0.05)"),
                    "color": ("#0A0A0A" if is_user else "rgba(255,255,255,0.85)"),
                    "fontSize": "12.5px",
                    "lineHeight": "1.5",
                    "border": ("none" if is_user else "0.5px solid rgba(255,255,255,0.08)"),
                    "borderLeft": ("none" if (is_user or (not walker_name)) else ("2px solid " + color)),
                    "fontWeight": ("500" if is_user else "400")
                }}>
                    {text}
                </div>
            </div>
        </div>;
}
