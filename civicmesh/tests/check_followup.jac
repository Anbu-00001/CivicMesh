"""Which messages count as a follow-up question, and which don't. The controls
matter as much: a real need that merely sounds like a question ("my landlord is
going to report me to ICE", "I need a phone") must get the ordinary answer.
Exit code 1 on any miss.
"""
import sys;
import from engine.followup { followup_intent, app_answer, program_answer, target_program, can_answer }

glob CASES: list = [
    ("who are you", "who"), ("are you a real person", "who"), ("is this a bot?", "who"), ("¿eres una persona?", "who"), ("¿Con quién hablo?", "who"),
    ("is this private", "private"), ("will you report me to ICE", "private"), ("¿Esto es privado? ¿le dirán a inmigración?", "private"), ("do you save my messages", "private"), ("who can see this", "private"),
    ("he's reading my phone, how do I delete this", "delete"), ("how do I delete my data", "delete"), ("¿cómo borro esto?", "delete"), ("mi esposo revisa mi celular", "delete"),
    ("what's the phone number", "phone"), ("whats the number", "phone"), ("who do I call", "phone"), ("¿cuál es el número?", "phone"),
    ("how do I apply for SNAP?", "apply"), ("how do I sign up", "apply"), ("¿cómo solicito?", "apply"),
    ("what documents do I need", "docs"), ("what do I need to bring", "docs"), ("¿qué papeles necesito?", "docs"),
    ("how long does it take", "long"), ("how long", "long"), ("¿cuánto tarda?", "long"),
    ("can you call them for me", "call"), ("can you apply for me", "call"), ("¿puedes llamar por mí?", "call"),
    # Needs and stories that sound like the above.
    ("my landlord is going to report me to ICE", ""), ("I need a phone", ""), ("can you tell me what programs there are", ""),
    ("how do I remove mold from my apartment", ""), ("how long can I stay in a shelter", ""), ("how long before I get evicted", ""),
    ("where do I go tonight", ""), ("mi madre es una persona mayor", ""), ("mi casero dice que me van a reportar", ""),
    ("how do I clear my record", ""), ("can you tell me more", ""), ("will you tell me if I qualify", ""), ("will you tell the police if I need help", "private"), ("I need food", ""), ("we are 4 people", "")
];

with entry {
    misses = 0;
    for (text, want) in CASES {
        got = str(followup_intent(text).get("intent", ""));
        if got != want {
            print(f"  ✗ {text!r}: want {want!r} got {got!r}");
            misses += 1;
        }
    }
    snap = {"resource_name": "SNAP (Supplemental Nutrition Assistance Program)", "contact_phone": "1-800-221-5689", "online_url": "https://example.gov/snap", "tier": "likely",
            "form": {"required_documents": ["Photo ID"], "estimated_minutes": 40, "url": ""}};
    wic = {"resource_name": "WIC", "contact_phone": "", "online_url": "https://example.gov/wic", "tier": "possible", "form": {}};
    if target_program("how do I apply for wic", [snap, wic], {}) != wic { print("  ✗ a named program is the target"); misses += 1; }
    if target_program("how do I apply", [snap, wic], {"steps": [{"agency_name": "WIC"}]}) != wic { print("  ✗ the first plan step is the target"); misses += 1; }
    for (intent, ranked, want) in [("phone", [snap], "1-800-221-5689"), ("phone", [wic], "example.gov/wic"), ("apply", [wic], "example.gov/wic"), ("docs", [snap], "Photo ID"), ("docs", [wic], "2-1-1"), ("long", [snap], "40 minutes"), ("long", [wic], "Only"), ("call", [snap], "1-800-221-5689"), ("call", [wic], "can't make calls"), ("phone", [], "kind of help")] {
        ans = program_answer({"intent": intent, "kind": "program"}, "en", "x", ranked, {});
        if want not in ans { print(f"  ✗ {intent}: {ans!r} lacks {want!r}"); misses += 1; }
    }
    for intent in ["who", "private", "delete"] {
        for lang in ["en", "es"] {
            if not app_answer({"intent": intent, "kind": "app"}, lang) { print(f"  ✗ no {intent} answer in {lang}"); misses += 1; }
        }
    }
    # A chip's English words on a Chinese page must not bring an English answer.
    if can_answer("zh") or not can_answer("es") { print("  ✗ only pages in English and Spanish get these answers"); misses += 1; }
    print(f"follow-ups: {len(CASES)} messages, {misses} misses");
    if misses { sys.exit(1); }
}
