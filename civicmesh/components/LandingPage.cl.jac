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

def:pub LandingPage(on_start: Any, platform: Any = None) -> JsxElement {

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
    def previewLine(step: int) -> str;

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
                        {("engine live · " + str(platform["programs"]) + " programs") if platform else "engine starting…"}
                    </span>
                    <div style={{"width": "1px", "height": "16px", "background": "rgba(255,255,255,0.1)", "margin": "0 6px"}}/>
                    <span style={{"fontSize": "11px", "color": "rgba(255,255,255,0.62)"}}>
                        JacHacks Spring 2026
                    </span>
                </div>
            </header>

            <section
                className="lp-reveal"
                role="main"
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
                    Jac walkers · deterministic eligibility engine · one LLM call, off the critical path
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
                    A multi-agent navigator that routes people in crisis — single mothers, immigrant families, elderly tenants — to the housing, food, healthcare and legal aid they qualify for, and shows exactly why. The whole answer composed in 51 languages on the first response, understood in 75, translated in 111 immigrant languages and dialects, and an interpreter card for the ones machines can't translate yet.
                </p>

                <div style={{"display": "flex", "justifyContent": "center", "alignItems": "center", "gap": "16px", "marginBottom": "56px", "flexWrap": "wrap"}}>
                    <button className="lp-cta" onClick={lambda _e: MouseEvent { on_start(); }}>
                        Enter the Navigator  →
                    </button>
                    <div style={{"fontSize": "12px", "color": "rgba(255,255,255,0.62)", "textAlign": "left", "lineHeight": "1.5"}}>
                        <div style={{"color": "rgba(255,255,255,0.65)"}}>No signup — an anonymous account lives in this browser</div>
                        <div>{"40 national programs · 2026 federal income rules · local offices from HUD & HRSA open data"}</div>
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
                            <span style={{"fontSize": "11px", "color": "rgba(255,255,255,0.62)", "marginLeft": "10px", "letterSpacing": "0.02em"}}>
                                {"Live engine run · " + ((str(platform["preview"]["engine_ms"]) + " ms, 0 LLM calls") if platform else "starting…")}
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
                        {(preview_step >= 1) and renderPreviewBubble("user", "", (str(platform["preview"]["prompt"]) if platform else "I'm a single mom with 2 kids in Houston. I earn $1,800 a month and we need food."), "#FFE500")}
                        {(preview_step >= 2) and renderPreviewBubble("bot", "IntakeWalker", previewLine(2), "#FFE500")}
                        {(preview_step >= 3) and renderPreviewBubble("bot", "EligibilityWalker", previewLine(3), "#4488FF")}
                        {(preview_step >= 4) and renderPreviewBubble("bot", "Next question", previewLine(4), "#00FF88")}
                        {(preview_step > 0 and preview_step < 4) and <div style={{"display": "flex", "alignItems": "center", "gap": "6px", "color": "rgba(255,255,255,0.62)", "fontSize": "11px", "fontStyle": "italic", "paddingLeft": "34px"}}>
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
                    {renderStatTile((str(platform["programs"]) if platform else "40"), "Programs scored per turn", "Federal + national programs · 2026 poverty & HUD limits by household size", "#FFE500")}
                    {renderStatTile((str(platform["languages_native"]) if (platform and platform["languages_native"]) else "51"), "Languages answered natively", ("Whole answer composed from reviewed templates · " + (str(platform["languages_routed"]) if platform else "75") + " routed without an LLM"), "#00FF88")}
                    {renderStatTile(((str(platform["stats"]["engine_ms_p50"]) + " ms") if (platform and Number(platform["stats"]["turns"]) > 0) else "< 1 s"), "Median engine time per turn", ((str(platform["stats"]["turns"]) + " live turns since last restart") if (platform and Number(platform["stats"]["turns"]) > 0) else "Answer on screen before any LLM call"), "#4488FF")}
                    {renderStatTile("1", "LLM call per turn", "Async narration with a facts guard — never on the critical path", "#FF88AA")}
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
                        Nine walkers, one traced pipeline.
                    </h2>
                    <p style={{"fontSize": "14px", "color": "rgba(255,255,255,0.5)", "margin": "0", "maxWidth": "560px", "marginLeft": "auto", "marginRight": "auto"}}>
                        Each walker owns one concern and writes its result to the graph. Escalation, Memory (outcome learning) and Critique run alongside these five.
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
                        {renderWalkerCard(1, "Intake",      "Identifies the language and need in 75 languages with evidence spans; an LLM only if nothing routes (3.5 s cap)", "#FFE500", "-3deg")}
                        {renderWalkerCard(2, "Eligibility", "Scores every program with effective-dated 2026 rules, calibrated tiers and Beta approval odds; writes eligible_for edges", "#4488FF", "2deg")}
                        {renderWalkerCard(3, "Navigation",  "Orders the plan by Smith's rule, merges shared documents, persists ApplicationNodes",   "#00FF88", "-2deg")}
                        {renderWalkerCard(4, "Pathfinder",  "Yen k-shortest expected-cost routes over leads_to edges",      "#FFB344", "3deg")}
                        {renderWalkerCard(5, "Narrator",    "The one LLM call: a summary in the user's language, after the answer is on screen", "#FF88AA", "-2deg")}
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
                        "color": "rgba(255,255,255,0.62)",
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
                        — example situation · paste it into the Navigator to see the real answer
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
                        "color": "rgba(255,255,255,0.62)",
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
                    "color": "rgba(255,255,255,0.62)",
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
                    · narration only
                </span>
                <span>
                    JacHacks Spring 2026
                </span>
            </footer>
        </div>;
}
