"""Questions about the answer or the app, asked in a later turn: "what's the phone
number", "how do I apply for SNAP?", "is this private", "he's reading my phone, how
do I delete this". A blind audit (2026-11-02) found they got the same answer again
and the next question, or the quiet reply with the cards gone.

Read in English and Spanish, and answered only on a page in one of them: a chip's
payload is English on every page, and a Chinese page has to keep answering in
Chinese. Other languages keep the ordinary answer. Nothing here is a model's: every
sentence is below or a program's own field. No crisis text is ever replaced:
walkers/eligibility.jac puts the answer in front of it.

What the private answer says has to stay true of PRIVACY.md and of the list in
ChatPane.renderPrivacy. Quick exit erases things only in a private session
(frontend.impl.jac), so the delete answer doesn't claim it does.
"""
import re;

glob APP_INTENTS: dict = {
    "delete": [
        "\\b(?:how (?:do|can|could) (?:i|we)|can i|need to|want to|help me) (?:delete|erase|clear|hide|remove) (?:this|it|that|everything|my (?:data|history|chat|messages?|case|info\\w*)|the (?:chat|history|conversation|messages?))\\b|\\bdelete (?:this|my|the) (?:chat|history|conversation|data|messages?)\\b|\\b(?:reads?|reading|checks?|checking|looks? through|looking through|goes through|going through|sees?) my (?:phone|messages|texts)\\b",
        "\\b(?:borro|borrar|elimino|eliminar) (?:esto|todo|el chat|mi historial|la conversaci[oó]n|mis datos)\\b|\\b(?:revisa|lee|mira|ve) mi (?:celular|tel[eé]fono|m[oó]vil)\\b"
    ],
    "private": [
        "\\bis (?:this|it|that|my \\w+) (?:really |actually )?(?:private|confidential|anonymous|secure)\\b|\\b(?:will|would|do|are|can) (?:you|this (?:site|app|tool|chat|website)|anyone)(?: going to)? (?:tell|report|turn \\w+ in)\\b[^.?!]{0,30}\\b(?:ice|immigration|police|cops|landlord|government|anyone|authorities|la migra)\\b|\\b(?:will|would|do|are|can) (?:you|this (?:site|app|tool|chat|website))(?: going to)? (?:report|turn) (?:me|us)\\b|\\b(?:will|do|are|can) (?:you|this (?:site|app|tool|chat|website)|anyone)(?: going to)? (?:share|sell|save|keep|store|see|read)\\b (?:my|this|what)\\b|\\bwho (?:can|will) (?:see|read) (?:this|it|my|what)\\b",
        "\\b(?:es|esto es|ser[aá]) (?:privado|confidencial|an[oó]nimo|seguro)\\b|\\ble (?:dir[aá]n|dir[aá]s|avisar[aá]n|contar[aá]n) a\\b|^\\W*(?:¿\\s*)?(?:ustedes )?me (?:van a|vas a|va a) (?:reportar|denunciar|delatar)\\b|\\bqui[eé]n (?:puede|va a) (?:ver|leer)\\b"
    ],
    "who": [
        "\\bwho are you\\b|\\bwhat are you\\b|\\bare you (?:a |an )?(?:real|human|person|bot|robot|ai|machine|computer)\\b|\\bis this (?:a )?(?:real person|human|person|bot|robot|ai)\\b|\\bam i (?:talking|speaking|chatting) (?:to|with)\\b|\\bwho am i (?:talking|speaking)\\b",
        "\\bqui[eé]n eres\\b|\\bqu[eé] eres\\b|\\beres (?:una )?(?:persona|humano|humana|robot|real|m[aá]quina)\\b|^\\W*(?:¿\\s*)?es una persona\\b|\\bcon qui[eé]n hablo\\b"
    ]
};

glob PROGRAM_INTENTS: dict = {
    "call": [
        "\\b(?:can|could|will|would) you (?:please )?(?:call|phone|contact|apply|fill|sign me up|do (?:it|this|that))\\b",
        "\\b(?:puedes|podr[ií]as|pueden|puede usted) (?:llamar|hablar|aplicar|llenar|hacerlo)\\b|\\bllam(?:a|ar|e) por m[ií]\\b"
    ],
    "phone": [
        "\\b(?:what(?:'?s| is)|whats|give me|send me|need|got) (?:the |their |a )?(?:phone |tele)?number\\b|\\bwhat(?:'?s| is) (?:the|their) phone\\b|\\bphone number\\b|\\bwho do i call\\b|\\bwhat number\\b|\\bhow (?:do|can) i (?:call|reach|contact)\\b",
        "\\b(?:cu[aá]l es|dame|p[aá]same) (?:el|su) (?:n[uú]mero|tel[eé]fono)\\b|\\ba qu[eé] n[uú]mero\\b|\\ba qui[eé]n llamo\\b"
    ],
    "docs": [
        "\\bwhat (?:documents?|papers?|paperwork|forms?|id)\\b|\\bwhat (?:do|should|would|will) (?:i|we) (?:need to |have to )?(?:bring|take|show)\\b|\\bwhat do (?:i|we) need (?:to apply|for it|for that)?\\W*$",
        "\\bqu[eé] (?:documentos|papeles)\\b|\\bqu[eé] (?:debo|tengo que|necesito) (?:llevar|traer|mostrar)\\b"
    ],
    "long": [
        "\\bhow long (?:does|will|would|do|is|until|before)\\s+(?:it|this|that|the (?:application|process|approval|form|wait))\\b|\\bhow long\\W*$|\\bhow long (?:for|until) (?:an answer|approval|i hear)\\b|\\bwhen (?:will|do|would|can) (?:i|we) (?:hear|know)\\b",
        "\\bcu[aá]nto (?:tiempo )?(?:tarda|toma|demora|se tarda)\\b|\\bcu[aá]ndo (?:sabr[eé]|me avisan|recibir[eé])\\b"
    ],
    "apply": [
        "\\bhow (?:do|can|would|should) (?:i|we) (?:apply|sign up|start|get (?:it|this|that|on)|enroll)\\b|\\bwhere (?:do|can) (?:i|we) (?:apply|sign up)\\b|\\bhow to apply\\b",
        "\\bc[oó]mo (?:puedo )?(?:aplico|aplicar|solicito|solicitar|me inscribo|inscribirme)\\b|\\bd[oó]nde (?:puedo )?(?:aplico|aplicar|solicito|solicitar)\\b"
    ]
};

glob ANSWERS: dict = {
    "en": {
        "who": "I'm an automated guide, not a person. I follow written rules to find programs you may qualify for, but only each program's office can decide. To talk to a person, call 2-1-1.",
        "private": "This tool doesn't report you. It doesn't contact ICE, the police or any office, and it never asks your name. What you type is read to find programs and isn't saved. Only what it understood (the kind of help, household size, income) stays, until you press Delete my data or the server restarts. Hugging Face, which hosts this site, sees ordinary web traffic such as your IP address. A court order could reach what is kept. Details are under Private by design, at the bottom of the chat.",
        "delete": "Quick exit leaves this page at once. To erase your case, open Private by design at the bottom of the chat and press Delete my data. Then delete this site from your browser history. If someone can check this phone, a friend's phone or a library computer is safer. National Domestic Violence Hotline: 1-800-799-7233.",
        "phone": "{program}: call {phone}.",
        "no_phone": "I don't have a phone number for {program}. Go to {url}, or call 2-1-1 to find the office.",
        "apply": "To apply for {program}: {how}",
        "how_url": "go to {url}.",
        "how_phone": "call {phone}.",
        "how_both": "go to {url}, or call {phone}.",
        "how_none": "call 2-1-1 to find the office.",
        "docs": "For {program}, bring: {docs}. Ask the office if you don't have something: they may take other proof.",
        "no_docs": "I don't have a list of papers for {program}. {ask}",
        "ask_phone": "Ask the office first: {phone}.",
        "ask_211": "Call 2-1-1 to find the office and ask.",
        "long": "The {program} form takes about {minutes} minutes. Only the office can say when you'll hear back, so ask when you apply.",
        "no_long": "Only the {program} office can say how long it takes, so ask when you apply.",
        "call": "I can't make calls or apply for you. You can call {program} at {phone}. 2-1-1 can also help you find the right office.",
        "no_call": "I can't make calls or apply for you. 2-1-1 can help you find the right office.",
        "none": "Tell me what kind of help you need first, and I'll find the program and how to reach it. You can also call 2-1-1."
    },
    "es": {
        "who": "Soy una guía automática, no una persona. Sigo reglas escritas para encontrar programas para los que podría calificar, pero solo la oficina de cada programa puede decidir. Para hablar con una persona, llame al 2-1-1.",
        "private": "Esta herramienta no lo denuncia. No se comunica con ICE, ni con la policía ni con ninguna oficina, y nunca le pide su nombre. Lo que escribe se lee para buscar programas y no se guarda. Solo queda lo que entendió (el tipo de ayuda, el tamaño del hogar, los ingresos), hasta que presione Delete my data (borrar mis datos) o se reinicie el servidor. Hugging Face, que aloja este sitio, ve el tráfico normal de la web, como su dirección IP. Una orden judicial podría alcanzar lo que se guarda. Los detalles están en Private by design, al final del chat.",
        "delete": "Quick exit (salida rápida) sale de esta página de inmediato. Para borrar su caso, abra Private by design al final del chat y presione Delete my data (borrar mis datos). Luego borre este sitio del historial del navegador. Si alguien puede revisar este teléfono, es más seguro usar el de una amistad o una computadora de la biblioteca. Línea Nacional de Violencia Doméstica: 1-800-799-7233.",
        "phone": "{program}: llame al {phone}.",
        "no_phone": "No tengo un número de teléfono de {program}. Vaya a {url} o llame al 2-1-1 para encontrar la oficina.",
        "apply": "Para solicitar {program}: {how}",
        "how_url": "vaya a {url}.",
        "how_phone": "llame al {phone}.",
        "how_both": "vaya a {url} o llame al {phone}.",
        "how_none": "llame al 2-1-1 para encontrar la oficina.",
        "docs": "Para {program}, lleve: {docs}. Si le falta algo, pregunte en la oficina: pueden aceptar otra prueba.",
        "no_docs": "No tengo una lista de papeles para {program}. {ask}",
        "ask_phone": "Pregunte primero a la oficina: {phone}.",
        "ask_211": "Llame al 2-1-1 para encontrar la oficina y preguntar.",
        "long": "El formulario de {program} toma unos {minutes} minutos. Solo la oficina puede decir cuándo tendrá respuesta, así que pregunte al solicitar.",
        "no_long": "Solo la oficina de {program} puede decir cuánto tarda, así que pregunte al solicitar.",
        "call": "No puedo hacer llamadas ni solicitar por usted. Puede llamar a {program} al {phone}. El 2-1-1 también puede ayudarle a encontrar la oficina correcta.",
        "no_call": "No puedo hacer llamadas ni solicitar por usted. El 2-1-1 puede ayudarle a encontrar la oficina correcta.",
        "none": "Primero dígame qué tipo de ayuda necesita y le busco el programa y cómo comunicarse. También puede llamar al 2-1-1."
    }
};

# Long messages are stories, and the questions in them get the ordinary answer.
glob FOLLOWUP_MAX_CHARS: int = 140;

"""The question being asked: {"intent", "kind": "app" | "program"}, or {}."""
def followup_intent(text: str) -> dict {
    low = re.sub("[’‘ʼ′＇`´]", "'", str(text)).lower().strip();
    if not low or len(low) > FOLLOWUP_MAX_CHARS { return {}; }
    for (kind, table) in [("app", APP_INTENTS), ("program", PROGRAM_INTENTS)] {
        for (intent, patterns) in table.items() {
            for pat in patterns {
                if re.search(pat, low) { return {"intent": intent, "kind": kind}; }
            }
        }
    }
    return {};
}

"""The pages these answers are written for."""
def can_answer(page_lang: str) -> bool {
    return page_lang in ANSWERS;
}

def _say(lang: str, key: str, slots: dict = {}) -> str {
    return str(ANSWERS[lang][key]).format(**slots);
}

"""The answer to a question about the app."""
def app_answer(asked: dict, page_lang: str) -> str {
    return _say(page_lang, str(asked["intent"]));
}

def _short_name(name: str) -> str {
    n = str(name);
    return n[:n.index("(")].strip() if "(" in n and n.index("(") > 0 else n;
}

"""The program being asked about: one named in the words, else the first plan step,
else the best match. A pinned crisis line counts only when nothing else is left."""
def target_program(text: str, ranked: list, plan: dict) -> dict {
    low = str(text).lower();
    for s in ranked {
        name = str(s.get("resource_name", ""));
        for candidate in [_short_name(name), name[name.index("(") + 1:name.index(")")] if "(" in name and ")" in name else ""] {
            if candidate and re.search("\\b" + re.escape(candidate.lower()) + "\\b", low) { return s; }
        }
    }
    steps = list(dict(plan or {}).get("steps", []));
    if steps {
        first = str(steps[0].get("agency_name", ""));
        for s in ranked {
            if str(s.get("resource_name", "")) == first { return s; }
        }
    }
    usable = [s for s in ranked if s.get("tier") != "unlikely" and not s.get("pinned", False)];
    if usable { return usable[0]; }
    return ranked[0] if ranked else {};
}

"""The answer to a question about a program in the current list."""
def program_answer(asked: dict, lang: str, text: str, ranked: list, plan: dict) -> str {
    intent = str(asked["intent"]);
    s = target_program(text, ranked, plan);
    if not s {
        return _say(lang, "none") if intent != "call" else _say(lang, "no_call");
    }
    program = _short_name(str(s.get("resource_name", "")));
    form = dict(s.get("form", {}) or {});
    phone = str(s.get("contact_phone", ""));
    url = str(s.get("online_url", "")) or str(form.get("url", ""));
    if intent == "phone" {
        if phone { return _say(lang, "phone", {"program": program, "phone": phone}); }
        return _say(lang, "no_phone", {"program": program, "url": url or "211.org"});
    }
    if intent == "call" {
        return _say(lang, "call", {"program": program, "phone": phone}) if phone else _say(lang, "no_call");
    }
    if intent == "apply" {
        how = _say(lang, "how_both", {"url": url, "phone": phone}) if (url and phone) else (_say(lang, "how_url", {"url": url}) if url else (_say(lang, "how_phone", {"phone": phone}) if phone else _say(lang, "how_none")));
        return _say(lang, "apply", {"program": program, "how": how});
    }
    if intent == "docs" {
        # The plan's list is the translated one, when this program is in the plan.
        step = [x for x in list(dict(plan or {}).get("steps", [])) if str(x.get("agency_name", "")) == str(s.get("resource_name", ""))];
        docs = [str(d) for d in list(step[0].get("documents_needed", []) if step else form.get("required_documents", []) or [])];
        if docs { return _say(lang, "docs", {"program": program, "docs": ", ".join(docs)}); }
        ask = _say(lang, "ask_phone", {"phone": phone}) if phone else _say(lang, "ask_211");
        return _say(lang, "no_docs", {"program": program, "ask": ask});
    }
    minutes = int(form.get("estimated_minutes", 0) or 0);
    if minutes > 0 { return _say(lang, "long", {"program": program, "minutes": minutes}); }
    return _say(lang, "no_long", {"program": program});
}
