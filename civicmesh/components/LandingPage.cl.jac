"""CivicMesh landing page.

First thing visitors see. Designed for the JacHacks demo screenshot:
glassmorphism + 3D-tilt walker pipeline + animated mesh background.
The "Enter Navigator" CTA flips ClientApp.show_landing=False and routes
to the chat tab — no walker spawns happen from this page.

Sections:
  - Glass nav strip with live status pill
  - Hero: massive headline with gradient text accent + glass preview card
  - Bento stat tiles (4 cards with 3D hover tilt)
  - Walker pipeline (5 cards alternating tilt, animated dashed rail under)
  - Persona pull-quote + persona chips
  - Tracks (3 glass pill badges)
  - Footer

All animation is CSS-only (mesh drift, gradient text shift, hover tilt,
dashed rail scroll). No Spline / WebGL — keeps bundle small and first
paint fast on 4G.
"""

def:pub LandingPage(on_start: Any) -> JsxElement {

    # Auto-typing chat preview state. The hero's "live session" glass card
    # advances bubble-by-bubble on a 1.4s cadence so judges see the agent
    # working before they scroll. preview_step ∈ [0..4]; 0 = nothing shown,
    # 4 = all four bubbles visible. Cycles back to 1 every ~9s so a judge
    # watching the page idle still sees motion.
    has preview_step: int = 0;

    can with entry {
        def advance(n: int) -> None {
            preview_step = n;
            if n < 4 {
                setTimeout(lambda { advance(n + 1); }, 1400);
            } else {
                setTimeout(lambda { advance(1); }, 4500);
            }
        }
        setTimeout(lambda { advance(1); }, 600);
    }

    def renderPersonaPill(label: str, color: str) -> JsxElement;
    def renderStatTile(value: str, label: str, sub: str, accent: str) -> JsxElement;
    def renderWalkerCard(idx: int, name: str, role: str, color: str, tilt: str) -> JsxElement;
    def renderTrackBadge(label: str, accent: str) -> JsxElement;
    def renderPreviewBubble(role: str, walker_name: str, text: str, color: str) -> JsxElement;

    return
        <div
            className="lp-root"
            style={{
                "minHeight": "100vh",
                "display": "flex",
                "flexDirection": "column",
                "background": "#070708",
                "color": "#FFFFFF",
                "fontFamily": "system-ui, -apple-system, sans-serif",
                "position": "relative",
                "overflow": "hidden"
            }}
        >
            <div className="lp-mesh"/>
            <div className="lp-grid"/>
            <div className="lp-noise"/>

            <header
                className="lp-glass"
                style={{
                    "position": "relative",
                    "zIndex": "10",
                    "margin": "20px 24px 0",
                    "padding": "12px 22px",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "space-between",
                    "borderRadius": "999px"
                }}
            >
                <div style={{"display": "flex", "alignItems": "center", "gap": "14px"}}>
                    <div style={{
                        "width": "30px",
                        "height": "30px",
                        "borderRadius": "9px",
                        "background": "linear-gradient(135deg, #FFE500 0%, #FF88AA 100%)",
                        "display": "flex",
                        "alignItems": "center",
                        "justifyContent": "center",
                        "fontWeight": "800",
                        "color": "#0A0A0A",
                        "fontSize": "14px",
                        "letterSpacing": "-0.04em",
                        "boxShadow": "0 6px 16px -4px rgba(255,229,0,0.45)"
                    }}>
                        CM
                    </div>
                    <span style={{"fontSize": "16px", "fontWeight": "700", "letterSpacing": "-0.02em"}}>
                        CivicMesh
                    </span>
                    <span style={{
                        "fontSize": "11px",
                        "padding": "3px 10px",
                        "borderRadius": "20px",
                        "background": "rgba(255,229,0,0.1)",
                        "color": "#FFE500",
                        "border": "0.5px solid rgba(255,229,0,0.3)",
                        "letterSpacing": "0.01em"
                    }}>
                        Agentic AI Navigator
                    </span>
                </div>
                <div style={{"display": "flex", "alignItems": "center", "gap": "10px"}}>
                    <div className="lp-pulse-dot"/>
                    <span style={{"fontSize": "12px", "color": "rgba(255,255,255,0.55)"}}>
                        llama-3.1-8b · live
                    </span>
                    <div style={{"width": "1px", "height": "16px", "background": "rgba(255,255,255,0.1)", "margin": "0 6px"}}/>
                    <span style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)"}}>
                        JacHacks Spring 2026
                    </span>
                </div>
            </header>

            <section
                className="lp-reveal"
                style={{
                    "position": "relative",
                    "zIndex": "1",
                    "padding": "70px 40px 50px",
                    "maxWidth": "1180px",
                    "margin": "0 auto",
                    "width": "100%",
                    "textAlign": "center"
                }}
            >
                <div className="lp-orb" style={{"width": "320px", "height": "320px", "background": "#FFE500", "top": "-40px", "left": "12%"}}/>
                <div className="lp-orb" style={{"width": "260px", "height": "260px", "background": "#FF88AA", "top": "40px", "right": "10%", "opacity": "0.35"}}/>

                <div style={{
                    "display": "inline-flex",
                    "alignItems": "center",
                    "gap": "8px",
                    "padding": "6px 14px",
                    "borderRadius": "999px",
                    "background": "rgba(255,255,255,0.05)",
                    "border": "0.5px solid rgba(255,255,255,0.12)",
                    "backdropFilter": "blur(12px)",
                    "fontSize": "12px",
                    "color": "rgba(255,255,255,0.7)",
                    "marginBottom": "26px",
                    "letterSpacing": "0.01em"
                }}>
                    <span style={{"width": "5px", "height": "5px", "borderRadius": "50%", "background": "#00FF88", "display": "inline-block", "boxShadow": "0 0 6px #00FF88"}}/>
                    Multi-agent · 5 specialized walkers · Jac + NVIDIA NIM
                </div>

                <h1 style={{
                    "fontSize": "78px",
                    "fontWeight": "800",
                    "letterSpacing": "-0.045em",
                    "lineHeight": "0.98",
                    "margin": "0 0 26px",
                    "color": "#FFFFFF"
                }}>
                    Every bureaucratic wall
                    <br/>
                    has a door.
                    <br/>
                    <span className="lp-gradient-text">CivicMesh finds it.</span>
                </h1>

                <p style={{
                    "fontSize": "18px",
                    "lineHeight": "1.6",
                    "color": "rgba(255,255,255,0.62)",
                    "maxWidth": "680px",
                    "margin": "0 auto 38px",
                    "fontWeight": "400"
                }}>
                    A multi-agent AI navigator that routes people in crisis — single mothers, undocumented families, elderly tenants — to the housing, food, healthcare and legal aid they qualify for. In any language. In under a minute.
                </p>

                <div style={{"display": "flex", "justifyContent": "center", "alignItems": "center", "gap": "16px", "marginBottom": "56px", "flexWrap": "wrap"}}>
                    <button className="lp-cta" onClick={lambda _e: MouseEvent { on_start(); }}>
                        Enter the Navigator  →
                    </button>
                    <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.4)", "textAlign": "left", "lineHeight": "1.5"}}>
                        <div style={{"color": "rgba(255,255,255,0.65)"}}>No signup · No data collection</div>
                        <div>Demo runs against 40 real seeded resources.</div>
                    </div>
                </div>

                <div
                    className="lp-glass-strong lp-float"
                    style={{
                        "position": "relative",
                        "maxWidth": "780px",
                        "margin": "0 auto",
                        "padding": "20px 22px",
                        "textAlign": "left"
                    }}
                >
                    <div style={{"display": "flex", "alignItems": "center", "justifyContent": "space-between", "marginBottom": "14px"}}>
                        <div style={{"display": "flex", "alignItems": "center", "gap": "8px"}}>
                            <span style={{"width": "10px", "height": "10px", "borderRadius": "50%", "background": "#FF5F57"}}/>
                            <span style={{"width": "10px", "height": "10px", "borderRadius": "50%", "background": "#FEBC2E"}}/>
                            <span style={{"width": "10px", "height": "10px", "borderRadius": "50%", "background": "#28C840"}}/>
                            <span style={{"fontSize": "11px", "color": "rgba(255,255,255,0.4)", "marginLeft": "10px", "letterSpacing": "0.02em"}}>
                                CivicMesh Navigator · live session
                            </span>
                        </div>
                        <div style={{
                            "display": "flex",
                            "alignItems": "center",
                            "gap": "6px",
                            "padding": "3px 10px",
                            "borderRadius": "20px",
                            "background": "rgba(255,229,0,0.1)",
                            "border": "0.5px solid rgba(255,229,0,0.3)",
                            "fontSize": "10px",
                            "color": "#FFE500"
                        }}>
                            <span style={{"width": "5px", "height": "5px", "borderRadius": "50%", "background": "#FFE500", "boxShadow": "0 0 5px #FFE500"}}/>
                            EligibilityWalker
                        </div>
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "10px", "minHeight": "180px"}}>
                        {(preview_step >= 1) and renderPreviewBubble("user", "",                  "Single mom · 2 kids · $1800/mo in Houston. Need help.", "#FFE500")}
                        {(preview_step >= 2) and renderPreviewBubble("bot",  "IntakeWalker",       "Detected: housing + food · urgency: immediate · ES/EN.", "#FFE500")}
                        {(preview_step >= 3) and renderPreviewBubble("bot",  "EligibilityWalker",  "Scored 40 resources. 12 eligible. Top: Section 8 (94), SNAP (89), WIC (82).", "#4488FF")}
                        {(preview_step >= 4) and renderPreviewBubble("bot",  "NavigationWalker",   "Built 4-step plan. Estimated $11,880/yr unlocked if approved.", "#00FF88")}
                        {(preview_step > 0 and preview_step < 4) and <div style={{"display": "flex", "alignItems": "center", "gap": "6px", "color": "rgba(255,255,255,0.35)", "fontSize": "11px", "fontStyle": "italic", "paddingLeft": "34px"}}>
                            <span className="lp-typing-dot"/>
                            <span className="lp-typing-dot"/>
                            <span className="lp-typing-dot"/>
                        </div>}
                    </div>
                </div>
            </section>

            <section
                style={{
                    "position": "relative",
                    "zIndex": "1",
                    "padding": "12px 40px 36px",
                    "maxWidth": "1180px",
                    "margin": "0 auto",
                    "width": "100%"
                }}
            >
                <div style={{
                    "display": "grid",
                    "gridTemplateColumns": "repeat(4, 1fr)",
                    "gap": "14px"
                }}>
                    {renderStatTile("40+",   "Resources seeded",        "Section 8 · SNAP · WIC · Medicaid · LIHEAP",            "#FFE500")}
                    {renderStatTile("5",     "AI agents collaborating", "Intake · Eligibility · Navigation · Memory · Escalation","#00FF88")}
                    {renderStatTile("∞",     "Languages supported",     "Detected per turn · routed via TranslateWalker",        "#4488FF")}
                    {renderStatTile("<12s",  "Median time per case",    "From free-form prompt to ranked action plan",           "#FF88AA")}
                </div>
            </section>

            <section
                style={{
                    "position": "relative",
                    "zIndex": "1",
                    "padding": "60px 40px",
                    "maxWidth": "1180px",
                    "margin": "0 auto",
                    "width": "100%"
                }}
            >
                <div className="lp-orb" style={{"width": "300px", "height": "300px", "background": "#4488FF", "top": "30px", "left": "-80px", "opacity": "0.3"}}/>

                <div style={{"textAlign": "center", "marginBottom": "40px"}}>
                    <div style={{
                        "display": "inline-flex",
                        "alignItems": "center",
                        "gap": "8px",
                        "padding": "5px 12px",
                        "borderRadius": "999px",
                        "background": "rgba(0,255,136,0.08)",
                        "border": "0.5px solid rgba(0,255,136,0.3)",
                        "fontSize": "10px",
                        "color": "#00FF88",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.1em",
                        "fontWeight": "600",
                        "marginBottom": "16px"
                    }}>
                        Architecture
                    </div>
                    <h2 style={{
                        "fontSize": "36px",
                        "fontWeight": "700",
                        "letterSpacing": "-0.025em",
                        "margin": "0 0 8px"
                    }}>
                        Five specialized walkers, one pipeline.
                    </h2>
                    <p style={{"fontSize": "14px", "color": "rgba(255,255,255,0.5)", "margin": "0", "maxWidth": "560px", "marginLeft": "auto", "marginRight": "auto"}}>
                        Each agent owns a single concern. Together they turn one prompt into a ranked, persisted action plan.
                    </p>
                </div>

                <div style={{"position": "relative"}}>
                    <div style={{
                        "position": "absolute",
                        "top": "78px",
                        "left": "8%",
                        "right": "8%",
                        "zIndex": "0"
                    }}>
                        <div className="lp-pipeline-rail"/>
                    </div>
                    <div style={{
                        "display": "grid",
                        "gridTemplateColumns": "repeat(5, 1fr)",
                        "gap": "14px",
                        "alignItems": "stretch",
                        "position": "relative",
                        "zIndex": "1"
                    }}>
                        {renderWalkerCard(1, "Intake",      "Extracts the user's need + language from free-form input", "#FFE500", "-3deg")}
                        {renderWalkerCard(2, "Eligibility", "Scores 40 resources against the profile via check_eligibility()", "#4488FF", "2deg")}
                        {renderWalkerCard(3, "Navigation",  "Builds an ordered ActionPlan, persists ApplicationNodes",   "#00FF88", "-2deg")}
                        {renderWalkerCard(4, "Memory",      "Stores session state on PersonNode for return visits",      "#FFB344", "3deg")}
                        {renderWalkerCard(5, "Escalation",  "ReAct loop with 3 tools for crisis routing when no match",  "#FF4444", "-2deg")}
                    </div>
                </div>
            </section>

            <section
                style={{
                    "position": "relative",
                    "zIndex": "1",
                    "padding": "30px 40px 60px",
                    "maxWidth": "1180px",
                    "margin": "0 auto",
                    "width": "100%",
                    "display": "grid",
                    "gridTemplateColumns": "1.4fr 1fr",
                    "gap": "20px",
                    "alignItems": "stretch"
                }}
            >
                <div
                    className="lp-glass"
                    style={{
                        "padding": "30px 32px",
                        "position": "relative",
                        "overflow": "hidden"
                    }}
                >
                    <div className="lp-orb" style={{"width": "240px", "height": "240px", "background": "#FFE500", "top": "-60px", "right": "-60px", "opacity": "0.18"}}/>
                    <div style={{
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.45)",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.1em",
                        "fontWeight": "600",
                        "marginBottom": "14px"
                    }}>
                        Who this is for
                    </div>
                    <div style={{
                        "fontSize": "26px",
                        "fontWeight": "700",
                        "letterSpacing": "-0.02em",
                        "lineHeight": "1.25",
                        "marginBottom": "18px"
                    }}>
                        "I'm a single mother with two kids and we just lost our apartment. I don't know what to do, and English is hard for me."
                    </div>
                    <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.5)", "marginBottom": "20px", "fontStyle": "italic"}}>
                        — Maria, demo persona · routed to Section 8 + SNAP + WIC in 11 seconds
                    </div>
                    <div style={{"display": "flex", "flexWrap": "wrap", "gap": "8px"}}>
                        {renderPersonaPill("Single mother · 2 kids · $1800/mo", "#FFE500")}
                        {renderPersonaPill("Undocumented family · healthcare", "#4488FF")}
                        {renderPersonaPill("Elderly tenant · fighting eviction", "#FF88AA")}
                        {renderPersonaPill("Veteran · housing instability", "#00FF88")}
                    </div>
                </div>

                <div
                    className="lp-glass"
                    style={{
                        "padding": "28px 30px",
                        "display": "flex",
                        "flexDirection": "column",
                        "justifyContent": "center",
                        "position": "relative",
                        "overflow": "hidden"
                    }}
                >
                    <div className="lp-orb" style={{"width": "200px", "height": "200px", "background": "#00FF88", "bottom": "-50px", "left": "-30px", "opacity": "0.2"}}/>
                    <div style={{
                        "fontSize": "10px",
                        "color": "rgba(255,255,255,0.45)",
                        "textTransform": "uppercase",
                        "letterSpacing": "0.1em",
                        "fontWeight": "600",
                        "marginBottom": "16px"
                    }}>
                        Competing in
                    </div>
                    <div style={{"display": "flex", "flexDirection": "column", "gap": "10px"}}>
                        {renderTrackBadge("Agentic AI",          "#FFE500")}
                        {renderTrackBadge("Consumer Healthcare", "#00FF88")}
                        {renderTrackBadge("Social Impact",       "#FF88AA")}
                    </div>
                </div>
            </section>

            <footer
                style={{
                    "marginTop": "auto",
                    "padding": "20px 40px",
                    "borderTop": "0.5px solid rgba(255,255,255,0.06)",
                    "fontSize": "11px",
                    "color": "rgba(255,255,255,0.35)",
                    "display": "flex",
                    "alignItems": "center",
                    "justifyContent": "space-between",
                    "position": "relative",
                    "zIndex": "1",
                    "backdropFilter": "blur(12px)"
                }}
            >
                <span>
                    Built on <span style={{"color": "rgba(255,229,0,0.7)", "fontWeight": "500"}}>Jac</span>
                    · Powered by <span style={{"color": "rgba(0,255,136,0.7)", "fontWeight": "500"}}>NVIDIA NIM</span>
                    · llama-3.1-8b-instruct
                </span>
                <span>
                    JacHacks Spring 2026
                </span>
            </footer>
        </div>;
}
