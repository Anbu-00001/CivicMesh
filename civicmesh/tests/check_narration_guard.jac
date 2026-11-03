"""The narration guard: invented programs and promises void a summary."""

import sys;
import from engine.narration_guard { invents_claims }

glob FACTS: str = "Matched: SNAP (likely), WIC (likely), Medicaid (possible). First step: apply for SNAP online. Question: how old are you?";
glob VOID: list = [
    "You should also apply for Section 8 right away.",
    "You can get TANF cash assistance too.",
    "Solicite también TANF para recibir dinero.",
    "आप TANF के लिए आवेदन कर सकते हैं।",
    "You will be approved for SNAP.",
    "SNAP benefits are guaranteed for your family.",
    "You definitely qualify for WIC.",
    "You're approved, just go to the office.",
    "Su solicitud de SNAP está garantizada.",
    "You'll receive SNAP within a week.",
    "You do not qualify for any program here. There is no point in calling anyone, so just wait and see.",
    "Do not call any hotline or apply for anything. Those offices report people to immigration and you could be deported.",
    "Things will not get better. You should stop looking for help.",
    "Good news: ignore any letter you get and stop paying your rent.",
    "Go to evil dot example slash claim and enter your Social Security number.",
    "You should apply to the Federal Emergency Cash Grant, which gives money to everyone.",
    "Your application has been accepted and a check is coming.",
    "No llame a nadie, deje de buscar ayuda."
];
glob KEEP: list = [
    "You likely qualify for SNAP and WIC. The first step is to apply for SNAP online.",
    "You may qualify for Medicaid once I know your age.",
    "If you qualify, you will receive a card in the mail.",
    "See if you qualify for WIC; how old are you?",
    "Probablemente califica para SNAP. Primero, solicite en línea.",
    "Start with snap applications online, then tell me your age.",
    "Here is what I found for you, and the next step to take.",
    "If you have trouble, call and ask for an interpreter. Keep any letter you get."
];

with entry {
    fails: list = [];
    for t in VOID { if not invents_claims(t, FACTS) { fails.append("should void: " + t); } }
    for t in KEEP { if invents_claims(t, FACTS) { fails.append("should keep: " + t); } }
    print("Narration guard: " + str(len(VOID) + len(KEEP)) + " checks");
    for f in fails { print("  ✗ " + f); }
    print("  " + ("PASS" if not fails else "FAIL (" + str(len(fails)) + ")"));
    if fails { sys.exit(1); }
}
