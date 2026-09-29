"""Deterministic intake parser — the zero-latency front of the pipeline.

Lifts a structured profile out of a free-form message in English or Spanish
with regex + weighted keyword evidence, in well under a millisecond. Every
extracted field carries the exact character span it came from, so the UI can
highlight *why* the agent believes something, and the pipeline gets a routing
confidence that decides whether the (slow) LLM is needed at all.

Output contract (plain dict so it serialises straight into walker reports):
  language, language_conf
  category, secondary, category_scores, category_conf
  urgency                    immediate | within_days | within_weeks
  income_annual              int, -1 = unknown (0 = stated no income)
  household_size, age        int, 0 = unknown
  state, city, zip
  citizenship                citizen | eligible_immigrant (green card) |
                             humanitarian (refugee/asylee/parolee) | non_citizen | ""
  flags                      senior, veteran, disabled, dv, self_harm, homeless,
                             children, pregnant, family
  evidence                   [{field, value, start, end, text}]
  completeness               share of the 5 eligibility fields that are known
  needs_llm, llm_reason      routing decision for the one LLM call
"""

import re;
import from engine.i18n { detect_script, detect_latin_other, route_i18n, negated, need_focus, LATIN_MARKERS, NEG_RIGHT }
import from engine.facts_i18n { facts_i18n }

# ---------- lexicons ----------
# (pattern, weight). Patterns are regex fragments matched on lowercase text
# with word boundaries, so "legal" never fires inside "illegally".
glob CATEGORY_LEXICON: dict = {
    "food": [
        ("food", 2.0), ("hungry", 2.0), ("hunger", 2.0), ("starving", 2.5),
        ("eat", 1.0), ("eaten", 2.0), ("meals?", 1.5), ("grocer(?:y|ies)", 1.5),
        ("snap", 2.5), ("wic", 2.0), ("food stamps", 2.5), ("pantry", 2.0),
        ("comida", 2.0), ("comer", 1.5), ("comido", 2.0), ("hambre", 2.5),
        ("alimentos?", 2.0), ("despensa", 2.0), ("cupones", 1.5),
        ("cook", 1.5), ("cooking", 1.5), ("cocinar", 1.5),
        ("(?:baby )?formula", 2.0), ("diapers?", 1.5), ("nothing to eat", 2.5),
        ("(?:fridge|refrigerator|pantry) is empty", 2.5), ("empty (?:fridge|refrigerator)", 2.5),
        ("grocery store", 2.0), ("get to the store", 2.0), ("pa[ñn]ales", 1.5), ("leche de f[oó]rmula", 2.0)
    ],
    "housing": [
        ("rent", 1.5), ("evict(?:ed|ion|ing)?", 2.5), ("landlord", 1.5),
        ("homeless", 2.5), ("shelter", 2.0), ("housing", 2.5), ("apartment", 1.0),
        ("section 8", 2.5), ("mortgage", 1.5), ("foreclos\\w*", 2.0),
        ("place to (?:stay|live|sleep)", 2.0), ("sleeping in (?:my|our|the) car", 2.5),
        ("renta", 1.5), ("alquiler", 1.5), ("desalo(?:jo|jar|jan)", 2.5),
        ("casero", 1.5), ("vivienda", 2.5), ("refugio", 2.0), ("sin hogar", 2.5),
        ("heating", 2.0), ("electric(?:ity)?", 1.5), ("utilit(?:y|ies)", 2.0),
        ("power bill", 2.0), ("gas bill", 2.0), ("shut ?off", 1.5),
        ("calefacci[oó]n", 2.0), ("luz", 1.0),
        ("place to (?:shower|wash)", 2.5), ("showers?", 1.5), ("laundry", 1.5),
        ("lugar (?:para|donde) (?:dormir|quedarnos|quedarme|vivir)", 2.5), ("d[oó]nde (?:dormir|vivir|quedarnos)", 2.0),
        ("no tengo (?:casa|hogar|d[oó]nde vivir)", 2.5)
    ],
    "healthcare": [
        ("doctor", 2.0), ("medicaid", 2.5), ("medicine", 2.0), ("medication", 2.0),
        ("prescriptions?", 2.0), ("hospital", 2.0), ("clinic", 2.0), ("dental", 2.0),
        ("dentist", 2.0), ("therapy", 1.5), ("mental health", 2.5), ("sick", 1.5),
        ("health insurance", 2.5), ("insulin", 2.5), ("depress\\w*", 1.5),
        ("m[eé]dico", 2.0), ("salud", 2.0), ("medicinas?", 2.0), ("cl[ií]nica", 2.0),
        ("enferm[oa]", 1.5), ("seguro m[eé]dico", 2.5),
        ("insurance", 1.0), ("treatment", 1.0), ("alcohol", 2.0), ("drugs?", 1.5),
        ("addict\\w*", 2.0), ("rehab", 2.0), ("hiv", 2.5), ("aids", 2.0),
        ("glasses", 2.0), ("eye exam", 2.5), ("vision", 1.5), ("toothache", 2.5),
        ("drogas", 1.5), ("adicci[oó]n", 2.0), ("lentes", 1.5)
    ],
    "legal": [
        ("lawyer", 2.5), ("attorney", 2.5), ("legal (?:aid|help|advice)", 2.5),
        ("court", 2.0), ("deport\\w*", 2.5), ("immigration", 2.0), ("asylum", 2.0),
        ("changed the locks", 2.5), ("locked (?:me |us )?out", 2.5), ("lockout", 2.5), ("cambi[oó] (?:la|las) cerradura", 2.5),
        ("mou?ld", 2.0), ("roach(?:es)?", 2.0), ("bed ?bugs", 2.0), ("repairs?", 1.5), ("won'?t fix", 2.0), ("refuses? to fix", 2.0), ("arreglar", 1.5),
        ("collections", 2.5), ("medical debt", 2.5),
        ("fired for", 2.5), ("wrongful(?:ly)? (?:termination|terminated|fired)", 2.5), ("fired", 1.0),
        ("visitation", 2.5), ("see my (?:kids|children|son|daughter|grandkids)", 2.0), ("child support", 2.5), ("divorce", 2.5), ("custodia", 2.5),
        ("arrest(?:ed)?", 2.5), ("jail", 2.0), ("charged with", 2.0), ("criminal record", 2.5),
        ("seal(?:ed|ing)? (?:my |his |her |the )?(?:criminal )?record", 2.5), ("record seal\\w*", 2.5),
        ("wages?", 2.0), ("unpaid (?:wages|pay|overtime)", 2.5), ("didn'?t pay me", 2.5), ("wage theft", 2.5),
        ("(?:security )?deposit back", 2.0), ("security deposit", 2.0), ("discriminat\\w*", 2.0),
        ("arrestad[oa]", 2.5), ("c[aá]rcel", 2.0), ("antecedentes", 2.0), ("salario no pagado", 2.5),
        ("illegal(?:ly)?", 1.5), ("my rights", 2.0), ("sue", 1.5), ("custody", 2.0),
        ("protective order", 2.5), ("expunge\\w*", 2.5), ("abogad[oa]", 2.5),
        ("corte", 2.0), ("tribunal", 2.0), ("deportaci[oó]n", 2.5),
        ("debt collectors?", 2.5), ("collection agenc(?:y|ies)", 2.5), ("collectors?", 1.5), ("loan", 1.0), ("scam\\w*", 2.0),
        ("fraud", 2.0), ("credit report", 2.0), ("cobrador", 2.0), ("estafa", 2.0),
        ("inmigraci[oó]n", 2.0), ("asilo", 2.0), ("derechos", 1.5)
    ]
};

glob FLAG_LEXICON: dict = {
    # "social security" alone is not an age: it's also a number, a card, an
    # office, SSDI and children's survivor benefits (outside probe: "I don't
    # have a social security number" made a mother of three a senior).
    "senior": ["senior", "elderly", "retired", "retiree", "social security (?:retirement|pension)", "jubilad[oa]", "ancian[oa]", "tercera edad"],
    # Service, not the word: "Salvation Army", "served in a restaurant" and a
    # job on a military base are not military service.
    "veteran": ["veterans?", "veteran[oa]s?", "ex-military", "served (?:my|our) country",
                "(?:served|serving|was|were|been|enlisted|joined|discharged|retired|got out)(?: \\w+)? (?:in|from|with)? ?(?:the )?(?:u\\.?s\\.? )?(?:army|navy|marines?|marine corps|air force|coast guard|national guard|military)",
                "(?:army|navy|marine|marines|air force|coast guard|national guard|military) (?:vet|veteran|service|retiree)",
                "dd-?214", "deployed to", "serv[ií] en (?:el |la )?(?:ej[eé]rcito|marina|fuerza a[eé]rea|infanter[ií]a|guardia nacional)", "(?:fui|era) (?:soldado|militar)", "militar retirad[oa]"],
    "disabled": ["disabilit(?:y|ies)", "disabled", "ssi", "ssdi", "wheelchair", "blind", "deaf", "discapacidad", "discapacitad[oa]"],
    "dv": ["domestic violence", "abus(?:e|ed|ive)", "hits me", "beats me", "hurts me", "safe house", "violencia dom[eé]stica", "maltrato", "me golpea",
           "(?:he|she)(?:'ll| will| might| could| is going to)? hurt me", "hurt me again", "(?:afraid|scared) (?:of )?(?:my )?(?:husband|boyfriend|partner|ex|wife|girlfriend)",
           "i'?m (?:scared|afraid) (?:that )?(?:he|she)", "me peg(?:a|[oó]|aba)", "me maltrata", "tengo miedo de mi (?:esposo|pareja|novio|ex)",
           # How people actually write it (external check: real posts, dev half only).
           "domestic (?:battery|abuse|assault|dispute|disturbance)", "restraining order", "protective order", "order of protection",
           "protection order", "no[- ]contact order", "my (?:attacker|abuser)", "sexually assaulted", "sexual assault", "raped",
           "(?:terrified|afraid|scared|fear(?:ful)?) for (?:my|her|his|our) (?:life|lives|safety)", "stalking (?:me|her|him)",
           "threatens (?:me|to hurt me|to kill me)", "fleeing (?:abuse|violence|domestic|my (?:husband|wife|partner|ex|boyfriend|girlfriend|abuser))",
           "(?:he|she|husband|wife|boyfriend|girlfriend|bf|gf|partner|spouse|fianc[eé]e?|ex|ex-husband|ex-wife|ex-boyfriend|ex-girlfriend|brother|sister|father|dad|stepdad|stepfather|mother|mom|stepmom|son|daughter|uncle|cousin|roommate|in-laws?)\\b[^.!?]{0,40}\\b(?:punched|kicked|choked|strangled|slapped|shoved|pushed|hit|beat|assaulted|attacked|raped|stabbed|threatened to kill|sucker punched|grabbed)\\b[^.!?]{0,15}\\b(?:me|her|him|us|my|our)",
           "(?:punched|kicked|choked|strangled|slapped|shoved|pushed|hit|beaten|assaulted|attacked|raped|abused|stabbed|threatened|sucker punched|battered) by (?:my|her|his|our|a|an) (?:\\w+ )?(?:he|she|husband|wife|boyfriend|girlfriend|bf|gf|partner|spouse|fianc[eé]e?|ex|ex-husband|ex-wife|ex-boyfriend|ex-girlfriend|brother|sister|father|dad|stepdad|stepfather|mother|mom|stepmom|son|daughter|uncle|cousin|roommate|in-laws?)"],
    "self_harm": ["suicid\\w*", "kill myself", "end my life", "want to die", "self[- ]harm", "hurt myself", "quitarme la vida", "matarme", "no quiero vivir",
                  "(?:don'?t|do not) want to (?:live|be alive|be here|wake up)", "no reason to (?:live|go on)", "better off dead", "end it all",
                  "take my (?:own )?life", "can'?t go on (?:anymore|like this)?", "quiero morir(?:me)?", "suicidarme", "no quiero seguir viviendo"],
    # "on the street" / "en la calle" only with a verb of living there: a car
    # parked on the street is not homelessness.
    "homeless": ["homeless", "on the streets", "(?:living|live|lived|sleeping|sleep|slept|staying|stay|ended up|end up|been|out) on the street",
                 "sleeping in (?:my|our|the|a) car", "nowhere to (?:go|stay|sleep|live)", "no place to (?:stay|sleep|live)", "(?:need|find|get) (?:a )?shelter tonight",
                 "sin hogar", "sin techo", "no tenemos d[oó]nde (?:vivir|dormir|quedarnos)",
                 "(?:vivo|vivimos|viv[ií]a|dormimos|duermo|dorm[ií]|estoy|estamos|quedamos|qued[eé]|terminamos|dejaron|echaron|sacaron|tiraron)(?: \\w+){0,2} en la calle"],
    "pregnant": ["pregnant", "expecting a baby", "embarazada"],
    "children": ["kids?", "children", "child", "sons?", "daughters?", "baby", "toddler", "infant", "teens?", "teenagers?", "hij[oa]s?", "ni[nñ][oa]s?", "beb[eé]"],
    "family": ["my family", "our family", "mi familia", "nuestra familia", "familia"]
};

# A personal fact is negated by "no / not / don't have / sin", and affirmed by
# "I have": the opposite of a need, where "I have food stamps" means I don't
# need them. (Outside probe: "I have nowhere to sleep" and "I have a son" lost
# their flags to the need rule; "I don't have a disability" kept its flag.)
glob FACT_NEG_LEFT: str = "(?:\\b(?:no|not|never|without|none of|isn'?t|aren'?t|wasn'?t|weren'?t|'m not|am not|'re not|are not|is not|don'?t have|do not have|doesn'?t have|does not have|didn'?t have|haven'?t got|haven'?t|have no|has no|had no)\\s+(?:a\\s+|an\\s+|any\\s+|the\\s+|my\\s+|our\\s+|really\\s+|actually\\s+|currently\\s+|yet\\s+)*|\\b(?:no tengo|no tenemos|no soy|no estoy|no estamos|no somos|sin|ni)\\s+(?:un\\s+|una\\s+|el\\s+|la\\s+|los\\s+|las\\s+|ning[uú]n\\s+|ninguna\\s+)*)$";

# Other senses of a flag's words, checked around each match. Crisis flags keep
# recall first: only clear non-crisis senses are excluded (a treatment program,
# a body part, an injury at work).
glob FLAG_SENSE_LEFT: dict = {
    "senior": "(?:high school|college|university)\\s+$",
    "dv": "(?:substance|drug|drugs|alcohol|opioid|opiate|elder care)\\s+$|(?:my|his|her|the)\\s+(?:back|head|leg|legs|knee|knees|tooth|teeth|foot|feet|stomach|chest|arm|arms|hand|hands|hip|neck|shoulder|eye|eyes|ear|body)\\s+$",
    "children": "(?:adult|grown|grown-up)\\s+$"
};
glob FLAG_SENSE_RIGHT: dict = {
    "senior": "^\\s+(?:at|in)\\s+(?:the\\s+|a\\s+|my\\s+)?(?:\\w+\\s+)?(?:college|high school|school|university)|^\\s+(?:year|center|centre|class|discount)|^\\s+from\\s+(?:the\\s+)?(?:u\\.?s\\.?\\s+)?(?:army|navy|marines?|marine corps|air force|coast guard|national guard|military|police|fire department)|^\\s+(?:at|at age|at the age of)\\s+[1-5]\\d\\b",
    "children": "^\\s+(?:are|is)\\s+(?:all\\s+)?(?:grown|adults?|over 18)|^\\s+(?:have\\s+|has\\s+)?(?:all\\s+)?moved out|^\\s+(?:don'?t|doesn'?t|do not|does not) live with (?:me|us)|^\\s*care\\s+(?:provider|worker|teacher|job|center|centre|business)|^\\s+support\\b",
    "self_harm": "^\\s+(?:at|on)\\s+(?:work|the job|my job)|^\\s+(?:lifting|falling|playing|cleaning|cooking|working|moving)|^\\s+(?:when|while) (?:i|lifting|falling|working|playing)|^\\s+in\\s+(?:a|an|the)\\s+(?:accident|fall|crash|car)"
};
# Intent words that keep a self-harm match even when an injury guard fires.
glob SELF_HARM_INTENT: str = "(?:want|wanted|wanna|going|gonna|trying|tried|tempted|urge|thinking about|thought about|feel like|on purpose|deliberately)";

"""True when a person-fact flag match is negated ("no kids", "not a veteran",
"don't have a disability", "no tengo hijos")."""
def fact_negated(low: str, start: int, end: int) -> bool {
    if re.search(FACT_NEG_LEFT, low[max(0, start - 32):start]) {
        return True;
    }
    return bool(re.search(NEG_RIGHT, low[end:end + 40]));
}

"""True when the match at [start, end) is this flag's word used in another sense."""
def flag_other_sense(flag: str, low: str, start: int, end: int) -> bool {
    left = low[max(0, start - 28):start];
    right = low[end:end + 40];
    lp = FLAG_SENSE_LEFT.get(flag, "");
    rp = FLAG_SENSE_RIGHT.get(flag, "");
    if lp and re.search(lp, left) { return True; }
    if flag == "dv" and low[start:end].startswith("hurts me") {
        # "hurts me" needs a person doing it, not a body part.
        return not re.search("(?:\\b(?:he|she|they|husband|wife|boyfriend|girlfriend|partner|ex|father|dad|stepdad|stepfather|mother|mom|stepmom|son|daughter|brother|sister|uncle|aunt|cousin|roommate|someone|somebody)\\b(?:\\s+\\w+){0,3}\\s+)$", left);
    }
    if rp and re.search(rp, right) {
        if flag == "self_harm" and re.search(SELF_HARM_INTENT, low[max(0, start - 40):end + 60]) { return False; }
        return True;
    }
    return False;
}

# A second, softer layer that can only escalate, never suppress: indirect ways
# of saying it, from the 988 Lifeline's warning signs ("being a burden",
# "feeling trapped", "no reason to live") and the National Domestic Violence
# Hotline's ("controls my money", "checks my phone", "threatens to take the
# kids", threats of deportation). An outside probe found 0 of 16 indirect
# messages caught by the direct lexicon. A concern pins the hotline as a
# gentle first line; it doesn't switch the turn into crisis mode.
glob CONCERN_LEXICON: dict = {
    "self_harm_concern": [
        "(?:better off|be better) without me", "(?:i'?m|i am|feel like) (?:just )?a burden", "burden (?:to|on) (?:everyone|my family|my kids|others|you all)",
        "no (?:reason|point) (?:to|in) (?:living|live|going on|being here|trying)", "(?:can'?t|cannot) (?:take|do|handle) (?:it|this|any of this) any ?more",
        "(?:feel|feeling|i'?m|i am) (?:so )?trapped(?! in (?:a|my|the|this) (?:lease|contract|job|loan|apartment|car|elevator|building))", "unbearable pain", "(?:wish|want) (?:it|everything|this) (?:would|to|could) (?:just )?(?:end|stop)",
        "wish i (?:was|were|could be) (?:dead|gone)", "wish i could (?:disappear|just disappear|not wake up)", "(?:don'?t|do not) see a way out",
        "no way out(?! of (?:the|this|my|a) (?:lease|contract|loan|deal|parking))", "tired of (?:living|being alive|life)", "giving away (?:all )?my (?:things|stuff|belongings)",
        "nobody would (?:care|miss me|notice) if i", "(?:estar[ií]an|estarian) mejor sin m[ií]", "soy una carga", "ya no puedo m[aá]s",
        "no (?:le )?veo (?:el )?sentido (?:a|de) (?:la vida|vivir|seguir)", "quisiera desaparecer", "no hay salida", "estoy cansad[oa] de vivir"],
    "dv_concern": [
        "(?:scared|afraid|terrified) (?:to|of going) (?:go )?(?:back )?home", "(?:don'?t|do not) feel safe (?:at|in my) home", "(?:isn'?t|is not|not) safe (?:at|in my) home",
        "(?:controls|takes|keeps) (?:all )?(?:my|our) (?:money|paycheck|cards?|documents|passport|papers)",
        "(?:checks|reads|goes through|tracks) my (?:phone|messages|texts|location|email)",
        "(?:won'?t|will not|doesn'?t|does not) let me (?:see|talk to|leave|work|go out|have a phone|call|visit)",
        "(?:threatens|threatened|says he'?ll|says she'?ll|keeps saying he'?ll|keeps saying she'?ll) (?:to )?(?:take (?:the|my) (?:kids|children)|call (?:immigration|ice)|report me|have me deported|deport me|kick me out)",
        "locks me (?:in|out)", "walking on eggshells", "(?:he|she) (?:gets|got) (?:really )?(?:violent|aggressive) when",
        "tengo miedo de (?:volver|regresar|ir) a (?:la )?casa", "me quita (?:el|mi) dinero", "(?:revisa|vigila) mi (?:tel[eé]fono|celular)",
        "no me deja (?:salir|trabajar|ver a mi familia|hablar con)", "amenaza con (?:quitarme a (?:los|mis) (?:ni[nñ]os|hijos)|llamar a inmigraci[oó]n|deportarme|echarme)",
        "no me siento segur[oa] en (?:mi )?casa"]
};

glob URGENT_PATTERNS: list = [
    "tonight", "right now", "today", "emergency", "immediately", "evicted",
    "eviction notice", "kicked out", "haven'?t eaten", "not eaten", "no food",
    "starving", "in danger", "no hemos comido", "no he comido", "esta noche",
    "ahora mismo", "urgente", "emergencia", "hoy"
];
glob SOON_PATTERNS: list = [
    "this week", "few days", "next week", "soon", "court date", "evict",
    "trying to evict", "behind on rent", "shut ?off", "esta semana", "pronto",
    "desalojo"
];

glob NUMBER_WORDS: dict = {
    "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5,
    "seis": 6, "siete": 7, "ocho": 8, "nueve": 9, "diez": 10
};

glob STATES: dict = {
    "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
    "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
    "florida": "FL", "georgia": "GA", "hawaii": "HI", "idaho": "ID",
    "illinois": "IL", "indiana": "IN", "iowa": "IA", "kansas": "KS",
    "kentucky": "KY", "louisiana": "LA", "maine": "ME", "maryland": "MD",
    "massachusetts": "MA", "michigan": "MI", "minnesota": "MN",
    "mississippi": "MS", "missouri": "MO", "montana": "MT", "nebraska": "NE",
    "nevada": "NV", "new hampshire": "NH", "new jersey": "NJ",
    "new mexico": "NM", "new york": "NY", "nueva york": "NY",
    "north carolina": "NC", "north dakota": "ND", "ohio": "OH",
    "oklahoma": "OK", "oregon": "OR", "pennsylvania": "PA",
    "rhode island": "RI", "south carolina": "SC", "south dakota": "SD",
    "tennessee": "TN", "texas": "TX", "utah": "UT", "vermont": "VT",
    "virginia": "VA", "washington": "WA", "west virginia": "WV",
    "wisconsin": "WI", "wyoming": "WY", "puerto rico": "PR"
};

glob CITIES: dict = {
    "houston": "TX", "dallas": "TX", "austin": "TX", "san antonio": "TX",
    "el paso": "TX", "los angeles": "CA", "san francisco": "CA",
    "san diego": "CA", "san jose": "CA", "oakland": "CA", "fresno": "CA",
    "nyc": "NY", "brooklyn": "NY", "bronx": "NY", "queens": "NY",
    "chicago": "IL", "miami": "FL", "orlando": "FL", "tampa": "FL",
    "phoenix": "AZ", "tucson": "AZ", "atlanta": "GA", "seattle": "WA",
    "boston": "MA", "philadelphia": "PA", "pittsburgh": "PA",
    "detroit": "MI", "denver": "CO", "las vegas": "NV", "portland": "OR",
    "minneapolis": "MN", "nashville": "TN", "memphis": "TN",
    "baltimore": "MD", "charlotte": "NC", "new orleans": "LA",
    "cleveland": "OH", "columbus": "OH", "albuquerque": "NM",
    # Cities many immigrant and refugee communities call home.
    "saint paul": "MN", "st. paul": "MN", "st paul": "MN", "sacramento": "CA",
    "dearborn": "MI", "hamtramck": "MI", "lowell": "MA", "long beach": "CA",
    "flushing": "NY", "edison": "NJ", "jersey city": "NJ", "newark": "NJ",
    "paterson": "NJ", "anaheim": "CA", "santa ana": "CA", "garden grove": "CA",
    "san gabriel": "CA", "fort worth": "TX", "silver spring": "MD",
    "falls church": "VA", "fairfax": "VA", "st. louis": "MO", "saint louis": "MO",
    "kansas city": "MO", "salt lake city": "UT", "boise": "ID", "omaha": "NE",
    "louisville": "KY", "indianapolis": "IN", "milwaukee": "WI", "buffalo": "NY",
    "syracuse": "NY", "utica": "NY", "providence": "RI", "hartford": "CT",
    "raleigh": "NC", "honolulu": "HI", "anchorage": "AK", "stockton": "CA",
    "modesto": "CA", "bakersfield": "CA", "riverside": "CA", "yuba city": "CA",
    "lewiston": "ME", "clarkston": "GA", "fargo": "ND", "sioux falls": "SD",
    "fort lauderdale": "FL", "jacksonville": "FL", "hialeah": "FL", "oklahoma city": "OK", "tulsa": "OK", "virginia beach": "VA", "colorado springs": "CO", "el cajon": "CA", "worcester": "MA", "des moines": "IA", "grand rapids": "MI", "spokane": "WA", "tacoma": "WA", "reno": "NV", "baton rouge": "LA", "birmingham": "AL", "little rock": "AR", "wichita": "KS", "durham": "NC", "knoxville": "TN"
};

glob EN_MARKERS: list = [
    "i", "i'm", "im", "my", "me", "the", "and", "is", "are", "have", "need",
    "help", "to", "for", "with", "we", "our", "you", "am", "was", "can",
    "what", "how", "where", "who", "don't", "haven't", "trying"
];
glob ES_MARKERS: list = [
    "y", "de", "la", "el", "en", "no", "mi", "yo", "para", "con", "que",
    "los", "las", "una", "un", "estoy", "estamos", "tengo", "tenemos",
    "necesito", "necesitamos", "ayuda", "hemos", "por", "del", "soy", "somos",
    "hijos", "familia", "días", "dias", "casa", "trabajo"
];

glob UNEARNED_CUES: str = r"\b(?:social security|ssi|ssdi|pension|disability (?:check|benefits?|payments?)|retirement (?:check|benefits?|income)|unemployment (?:benefits?|insurance|checks?)|child support|alimony|seguro social|pensi[oó]n|jubilaci[oó]n)\b";
glob EARNED_CUES: str = r"\b(?:earn|earns|earning|earnings|salary|wages?|paycheck|job|jobs|work|works|working|hourly|an hour|per hour|self.employed|sueldo|salario|trabajo)\b";
glob INCOME_CUES: str ="(?:earn|earning|make|making|income|salary|paid|wage|wages|pension|social security|ssi|ssdi|disability|benefits?|gano|ganamos|ingresos?|sueldo|salario|pensi[oó]n|seguro social)";
glob EXPENSE_CUES: str = "(?:rent|owe|owed|debt|bill|bills|cost|costs|fee|fine|deposit|renta|alquiler|debo|deuda|factura)";
glob MONEY_RE: str = "\\$\\s?(\\d[\\d,]*(?:\\.\\d+)?)\\s*(k)?|(\\d[\\d,]*(?:\\.\\d+)?)\\s*(k)?\\s*(?:dollars|d[oó]lares|usd|bucks)";
glob PERIOD_RE: str = "^\\s*(?:/|a|an|per|every|each|al|por|cada|a la|al a[nñ]o)?\\s*(month|mo|monthly|year|yr|yearly|annually|annual|week|wk|weekly|hour|hr|hourly|mes|mensual(?:es)?|a[nñ]o|anual(?:es)?|semana|semanal(?:es)?|hora)\\b";

# ---------- helpers ----------

"""Append one evidence record for a matched span."""
def _ev(evidence: list, field: str, value: any, start: int, end: int, text: str) -> None {
    evidence.append({"field": field, "value": value, "start": start, "end": end, "text": text[start:end]});
}

"""Resolve a digit string or number word ("two", "dos") to an int, 0 if unknown."""
def _num(tok: str) -> int {
    t = tok.strip().lower();
    if t.isdigit() {
        return int(t);
    }
    return int(NUMBER_WORDS.get(t, 0));
}

"""Detect the message language: script first, then Latin marker words.

Returns (code, confidence). A non-Latin script names the language outright
(engine/i18n.jac); Latin text is scored against English and Spanish marker
words here and against other Latin-script languages in i18n. "" means no
language could be identified — the narration call then writes back in
whatever language the user used.
"""
def detect_language(text: str) -> tuple {
    (sc, sconf) = detect_script(text);
    if sc {
        return (sc, sconf);
    }
    low = text.lower();
    words = re.findall(r"[a-záéíóúñü']+", low);
    en = 0;
    es = 0;
    for w in words {
        if w in EN_MARKERS { en += 1; }
        if w in ES_MARKERS { es += 1; }
    }
    # Accents are Spanish evidence only without letters Spanish never uses
    # (Portuguese ã õ ç ê ô, French è à ù î û ë ï œ).
    # An accented word that is a Portuguese marker ("família", "está") is not
    # Spanish evidence either.
    pt_words = set(LATIN_MARKERS.get("pt", []));
    accented = [w for w in words if re.search(r"[áéíóú]", w) and w not in pt_words];
    accent_es = (bool(re.search(r"[ñ¿¡]", low)) or len(accented) > 0) and not re.search(r"[ãõçêôâèàùîûëïœ]", low);
    if accent_es { es += 2; }
    (other, other_hits) = detect_latin_other(low);
    # Other languages are scored on distinct marker words, so compare them
    # with distinct EN/ES markers too — a long French text repeats "de",
    # "en", "la" often enough to out-count its own markers otherwise.
    wset = set(words);
    en_u = len([w for w in wset if w in EN_MARKERS]);
    es_u = len([w for w in wset if w in ES_MARKERS]) + (2 if accent_es else 0);
    if other and other_hits >= 2 and other_hits > max(en_u, es_u) {
        return (other, round(min(0.95, 0.5 + 0.08 * other_hits), 2));
    }
    total = en + es;
    # One stray marker ("mi") in a long sentence is not evidence of English
    # or Spanish — leave it unidentified and let the narrator mirror it.
    if total == 0 or (total == 1 and len(words) >= 5) {
        return ("", 0.0);
    }
    if en >= es {
        return ("en", round(min(1.0, 0.5 + (en - es) / (2.0 * total) + min(en, 4) * 0.1), 2));
    }
    return ("es", round(min(1.0, 0.5 + (es - en) / (2.0 * total) + min(es, 4) * 0.1), 2));
}

"""Score each need category from weighted keyword evidence."""
def score_categories(low: str, evidence: list, text: str) -> dict {
    scores: dict = {"food": 0.0, "housing": 0.0, "healthcare": 0.0, "legal": 0.0};
    for (cat, lex) in CATEGORY_LEXICON.items() {
        for (pat, w) in lex {
            for m in re.finditer("\\b" + pat + "\\b", low) {
                # "we're not homeless", "I don't need a lawyer", "we have food"
                if negated(low, m.start(), m.end()) { continue; }
                # The thing asked for outweighs context ("the shelter gave us
                # a bed, now I need a doctor").
                scores[cat] = scores[cat] + w + (1.0 if need_focus(low, m.start(), m.end()) else 0.0);
                _ev(evidence, "category", cat, m.start(), m.end(), text);
            }
        }
    }
    # An *unlawful* eviction is a tenant-rights (legal) problem first; the
    # housing programs still come along as the secondary category.
    if re.search(r"\billegal(?:ly)?\b|\bwithout (?:a )?notice\b|\bmy rights\b", low) and scores["housing"] > 0 {
        scores["legal"] = scores["legal"] + 3.0;
    }
    return scores;
}

"""Extract annual income in USD. Returns (income_annual, evidence_or_None).

Amounts in an expense context ("rent is $900") are ignored; a bare amount
without a period is read as monthly below $5k and annual above.
"""
def parse_income(low: str) -> tuple {
    if re.search(r"\b(?:no income|zero income|unemployed|lost (?:my|our) jobs?|no job|out of work|sin trabajo|sin empleo|no tengo (?:ingresos|trabajo)|desempleado|desempleada)\b", low) {
        m0 = re.search(r"\b(?:no income|zero income|unemployed|lost (?:my|our) jobs?|no job|out of work|sin trabajo|sin empleo|no tengo (?:ingresos|trabajo)|desempleado|desempleada)\b", low);
        return (0, m0);
    }
    best: any = None;
    best_score = -99.0;
    best_annual = -1;
    for m in re.finditer(MONEY_RE, low) {
        raw = m.group(1) or m.group(3);
        kflag = m.group(2) or m.group(4);
        try {
            amount = float(raw.replace(",", ""));
        } except Exception as _ex {
            continue;
        }
        if kflag { amount = amount * 1000.0; }
        tail = low[m.end():m.end() + 24];
        head = low[max(0, m.start() - 40):m.start()];
        pm = re.match(PERIOD_RE, tail);
        period = pm.group(1) if pm else "";
        cue = 0.0;
        if re.search(INCOME_CUES, head) or re.search(INCOME_CUES, tail) { cue += 2.0; }
        # Expense words only disqualify an amount inside the same clause
        # ("rent is $900"), not across a comma ("rent, family of 3, $25k a year").
        clause = re.split(r"[,.;!?]", head)[-1];
        if re.search(EXPENSE_CUES, clause) { cue -= 3.0; }
        if period { cue += 1.0; }
        if cue < 0 { continue; }
        annual = amount;
        if period.startswith("h") or period == "hora" {
            annual = amount * 2080.0;
        } elif period.startswith("w") or period.startswith("seman") {
            annual = amount * 52.0;
        } elif period.startswith("mo") or period.startswith("mes") or period.startswith("mensual") {
            annual = amount * 12.0;
        } elif period == "" and amount < 5000.0 {
            annual = amount * 12.0;
        }
        if cue > best_score {
            best_score = cue;
            best = m;
            best_annual = int(round(annual));
        }
    }
    return (best_annual, best);
}

"""Household size from explicit counts, children counts and partner mentions."""
def parse_household(low: str, evidence: list, text: str) -> int {
    m = re.search(r"\b(?:family|household) of (\d+|\w+)\b|\bfamilia de (\d+|\w+)\b|\bsomos (\d+|\w+)\b|\bwe are (\d+|\w+) (?:people|of us)\b|\bthere (?:are|is) (\d+|\w+) (?:people|persons|of us)\b|\b(\d+|\w+) (?:people|persons) (?:live|living|in (?:my|our|the) (?:house|home|household|apartment|family))\b", low);
    if m {
        tok = m.group(1) or m.group(2) or m.group(3) or m.group(4) or m.group(5) or m.group(6);
        n = _num(tok);
        if n > 0 and n < 20 {
            _ev(evidence, "household_size", n, m.start(), m.end(), text);
            return n;
        }
    }
    kids = 0;
    km = re.search(r"\b(\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|un|uno|una|dos|tres|cuatro|cinco|seis)\s+(?:little\s+|young\s+|small\s+)?(?:kids?|children|child|sons?|daughters?|babies|baby|dependents|grandchildren|grandkids|hij[oa]s|ni[nñ][oa]s|niet[oa]s|beb[eé]s?)\b", low);
    if km {
        kids = _num(km.group(1));
        if kids > 0 and kids < 15 {
            _ev(evidence, "household_size", kids, km.start(), km.end(), text);
        } else {
            kids = 0;
        }
    }
    partner = 1 if re.search(r"\b(?:my|our) (?:husband|wife|partner|spouse|boyfriend|girlfriend)\b|\bmi (?:esposo|esposa|pareja|marido|mujer)\b|\bmarried\b|\bcasad[oa]\b", low) else 0;
    # Someone fleeing an abusive partner is not in that partner's household.
    if partner and re.search(r"\b(?:hits|beats|hurts|abus\w*|threaten\w*)\b|\bme golpea\b|\bmaltrat\w*", low) {
        partner = 0;
    }
    if kids > 0 {
        return 1 + kids + partner;
    }
    if re.search(r"\b(?:i live alone|live by myself|just me|only me|vivo sol[oa])\b", low) {
        ma = re.search(r"\b(?:i live alone|live by myself|just me|only me|vivo sol[oa])\b", low);
        _ev(evidence, "household_size", 1, ma.start(), ma.end(), text);
        return 1;
    }
    if partner {
        return 2;
    }
    return 0;
}

"""Age from "I'm 72", "72 years old", "tengo 72 años"."""
def parse_age(low: str, evidence: list, text: str) -> int {
    for pat in [
        r"\b(?:i'?m|i am|aged?|age of)\s+(\d{2,3})\b(?!\s*(?:min|minutes|hours|days|months|weeks|dollars|%|k\b))",
        r"\b(\d{2,3})\s*(?:years? old|yrs? old|y/?o\b|year-old)",
        r"\btengo\s+(\d{2,3})\s+a[nñ]os\b",
        r"\b(\d{2,3})\s+a[nñ]os de edad\b",
        # A caregiver writing for someone else: the age of the person the help
        # is for ("my mom is 80", "mi padre tiene 75 años").
        r"\bmy\s+(?:elderly\s+)?(?:mom|mother|dad|father|grandma|grandmother|grandpa|grandfather|husband|wife|aunt|uncle|parents?)\s*(?:is|,)\s*(\d{2,3})\b(?!\s*(?:dollars|%|k\b|/))",
        r"\bmi\s+(?:mam[aá]|madre|pap[aá]|padre|abuel[oa]|espos[oa])\s+tiene\s+(\d{2,3})\b"
    ] {
        m = re.search(pat, low);
        if m {
            a = int(m.group(1));
            if a >= 14 and a <= 110 {
                _ev(evidence, "age", a, m.start(), m.end(), text);
                return a;
            }
        }
    }
    return 0;
}

"""State / city / zip. City implies state."""
def parse_location(text: str, low: str, evidence: list) -> dict {
    out: dict = {"state": "", "city": "", "zip": ""};
    # Letter lookarounds, not \b: CJK and other scripts count as word
    # characters, so "我住在Houston" has no \b before the H.
    for (city, st) in CITIES.items() {
        m = re.search("(?<![a-z])" + re.escape(city) + "(?![a-z])", low);
        if m {
            out["city"] = city.title();
            out["state"] = st;
            _ev(evidence, "location", city.title() + ", " + st, m.start(), m.end(), text);
            break;
        }
    }
    if not out["state"] {
        for (name, st) in STATES.items() {
            m = re.search("(?<![a-z])" + re.escape(name) + "(?![a-z])", low);
            if m {
                out["state"] = st;
                _ev(evidence, "location", st, m.start(), m.end(), text);
                break;
            }
        }
    }
    if not out["state"] {
        # Two-letter codes only in their capitalised form after "in" or a
        # comma, so "in" / "or" / "me" as words never match.
        m = re.search(r"(?:\bin |, )([A-Z]{2})\b", text);
        if m and m.group(1) in STATES.values() {
            out["state"] = m.group(1);
            _ev(evidence, "location", m.group(1), m.start(1), m.end(1), text);
        }
    }
    z = re.search(r"(?<![\$\d,.])\b(\d{5})\b(?![\d,.]|\s*(?:dollars|a (?:year|month)|/))", text);
    if z {
        out["zip"] = z.group(1);
        _ev(evidence, "location", z.group(1), z.start(1), z.end(1), text);
    }
    return out;
}

"""Citizenship / immigration status hints."""
def parse_citizenship(low: str, evidence: list, text: str) -> str {
    rules: list = [
        (r"\b(?:undocumented|no papers|without papers|no documents|illegal immigrant|not a (?:us )?citizen|out of status|indocumentad[oa]s?|sin papeles|sin documentos)\b", "non_citizen"),
        (r"\b(?:seeking asylum|asylum seeker|solicitando asilo|pidiendo asilo)\b", "non_citizen"),
        (r"\b(?:refugee|asylee|granted asylum|parolee|humanitarian parole|refugiad[oa]|asilad[oa]|asilo aprobado)\b", "humanitarian"),
        (r"\b(?:green card|permanent resident|lpr|residente permanente|tarjeta verde)\b", "eligible_immigrant"),
        (r"\b(?:daca|dreamer|visa holder|on a visa|work visa|tps)\b", "non_citizen"),
        # A temporary visa, stated by the speaker (external check: real posts
        # name the visa: "on the Visa Waiver Program", "my H4 status expired").
        # "Her visa is up" or "he'll get deported" is someone else's status.
        (r"\b(?:i'?m|i am|i was|we'?re|we are|we were|i have|i hold|i got|i came|we came|my|our)\b(?:(?!\w+'s\b)[^.!?]){0,30}\b(?:(?:h-?1b|h-?4|f-?1|j-?1|k-?1|b-?[12]|l-?1|o-?1|tn|student|tourist|work|visitor|fianc[eé]e?|spouse)\s+(?:visa|status)|visa waiver|visa|work permit|ead card|i-94)\b", "non_citizen"),
        (r"\b(?:i|we) (?:hold|have|got|received) (?:us |u\.s\. |american )?citizenship\b", "citizen"),
        (r"\b(?:us citizen|u\.s\. citizen|american citizen|citizen|born here|ciudadan[oa])\b", "citizen")
    ];
    for (pat, status) in rules {
        m = re.search(pat, low);
        if m {
            _ev(evidence, "citizenship", status, m.start(), m.end(), text);
            return status;
        }
    }
    return "";
}

# ---------- entry point ----------

"""Parse one user message into a structured, evidence-backed profile."""
def parse_intake(text: str) -> dict {
    raw = str(text or "");
    low = raw.lower();
    evidence: list = [];

    (lang, lang_conf) = detect_language(raw);

    scores = score_categories(low, evidence, raw);
    i18n_flags: list = [];
    i18n_urgent = False;
    if lang and lang not in ["en", "es"] {
        routed = route_i18n(lang, low);
        for (cat, v) in routed["scores"].items() {
            scores[cat] = float(scores[cat]) + float(v);
        }
        for sp in routed["spans"] {
            _ev(evidence, sp["field"], sp["value"], int(sp["start"]), int(sp["end"]), raw);
        }
        i18n_flags = list(routed["flags"]);
        i18n_urgent = bool(routed["urgent"]);
    }
    ranked = sorted(scores.items(), key=lambda kv: tuple : -kv[1]);
    top_cat = ranked[0][0] if ranked[0][1] > 0 else "";
    top_score = float(ranked[0][1]);
    second_score = float(ranked[1][1]);
    secondary: list = [c for (c, s) in ranked[1:] if s >= 1.5 and s >= top_score * 0.4];
    # Confidence: absolute evidence mass, penalised when two categories tie.
    cat_conf = 0.0;
    if top_score > 0 {
        margin = (top_score - second_score) / top_score;
        cat_conf = round(min(1.0, (top_score / 4.0)) * (0.55 + 0.45 * margin), 2);
    }

    flags: list = [];
    for (flag, pats) in FLAG_LEXICON.items() {
        hit: Any = None;
        for pat in pats {
            for m in re.finditer("\\b" + pat + "\\b", low) {
                # Crisis and violence flags are never negated away: a false
                # alarm shows a hotline, a miss hides one. Only clearly other
                # senses are excluded for them.
                if flag_other_sense(flag, low, m.start(), m.end()) { continue; }
                if flag not in ["self_harm", "dv"] and fact_negated(low, m.start(), m.end()) { continue; }
                hit = m;
                break;
            }
            if hit { break; }
        }
        if hit {
            flags.append(flag);
            _ev(evidence, "flag", flag, hit.start(), hit.end(), raw);
        }
    }
    for f in i18n_flags {
        if f not in flags { flags.append(f); }
    }
    # Indirect cues: added only when the direct flag isn't already there.
    for (cflag, cpats) in CONCERN_LEXICON.items() {
        direct = cflag.replace("_concern", "");
        if direct in flags { continue; }
        for cp in cpats {
            cm = re.search("\\b" + cp + "\\b", low);
            if cm {
                flags.append(cflag);
                _ev(evidence, "flag", cflag, cm.start(), cm.end(), raw);
                break;
            }
        }
    }
    # Crisis flags override the category router: they always need a human line.
    if "self_harm" in flags and not top_cat {
        top_cat = "healthcare";
        cat_conf = 0.9;
    }
    if "dv" in flags and not top_cat {
        top_cat = "housing";
        cat_conf = 0.8;
    }

    urgency = "within_weeks";
    for pat in URGENT_PATTERNS {
        m = re.search("\\b" + pat + "\\b", low);
        if m {
            urgency = "immediate";
            _ev(evidence, "urgency", "immediate", m.start(), m.end(), raw);
            break;
        }
    }
    if urgency != "immediate" {
        for pat in SOON_PATTERNS {
            m = re.search("\\b" + pat, low);
            if m {
                urgency = "within_days";
                _ev(evidence, "urgency", "within_days", m.start(), m.end(), raw);
                break;
            }
        }
    }
    if i18n_urgent or "self_harm" in flags or "dv" in flags or "homeless" in flags {
        urgency = "immediate";
    }
    # "haven't eaten in 2 days" / "no hemos comido en 2 días"
    if re.search(r"\b(?:haven'?t|have not|not) eaten\b|\bno (?:hemos|he) comido\b", low) {
        urgency = "immediate";
    }

    (income_annual, im) = parse_income(low);
    if im {
        _ev(evidence, "income", income_annual, im.start(), im.end(), raw);
        # SNAP's 20% deduction is for earnings only: "$1200/month Social
        # Security" is unearned income and gets no such deduction.
        ctx = low[max(0, im.start() - 40):im.end() + 24];
        if re.search(UNEARNED_CUES, ctx) and not re.search(EARNED_CUES, ctx) and "unearned_income" not in flags {
            flags.append("unearned_income");
        }
    }
    household = parse_household(low, evidence, raw);
    if household > 1 and "children" not in flags and re.search(r"\b(?:kids?|children|hij[oa]s|ni[nñ][oa]s)\b", low) {
        flags.append("children");
    }
    age = parse_age(low, evidence, raw);
    if age >= 60 and "senior" not in flags {
        flags.append("senior");
    }
    # A stated age wins over a word: "retired from the army at 42".
    if 0 < age < 60 and "senior" in flags {
        flags.remove("senior");
    }
    loc = parse_location(raw, low, evidence);
    citizenship = parse_citizenship(low, evidence, raw);

    # Other languages: the same five facts from per-language tables
    # (engine/facts_i18n.jac), filling whatever the EN/ES patterns missed.
    if lang and lang not in ["en", "es"] {
        fx = facts_i18n(lang, low, flags);
        if income_annual < 0 and int(fx["income_annual"]) >= 0 {
            income_annual = int(fx["income_annual"]);
            _ev(evidence, "income", income_annual, int(fx["income_span"][0]), int(fx["income_span"][1]), raw);
        }
        if household == 0 and int(fx["household_size"]) > 0 {
            household = int(fx["household_size"]);
            if int(fx["household_span"][0]) >= 0 {
                _ev(evidence, "household_size", household, int(fx["household_span"][0]), int(fx["household_span"][1]), raw);
            }
        }
        if int(fx["kids"]) > 0 and "children" not in flags { flags.append("children"); }
        if age == 0 and int(fx["age"]) > 0 {
            age = int(fx["age"]);
            _ev(evidence, "age", age, int(fx["age_span"][0]), int(fx["age_span"][1]), raw);
            if age >= 60 and "senior" not in flags { flags.append("senior"); }
        }
        if not citizenship and fx["citizenship"] {
            citizenship = str(fx["citizenship"]);
            _ev(evidence, "citizenship", citizenship, int(fx["citizenship_span"][0]), int(fx["citizenship_span"][1]), raw);
        }
        if not loc["state"] and fx["state"] {
            loc["state"] = str(fx["state"]);
            loc["city"] = str(fx["city"]);
            _ev(evidence, "location", ((str(fx["city"]) + ", ") if fx["city"] else "") + str(fx["state"]), int(fx["place_span"][0]), int(fx["place_span"][1]), raw);
        }
    }

    known = 0;
    if income_annual >= 0 { known += 1; }
    if household > 0 { known += 1; }
    if age > 0 { known += 1; }
    if loc["state"] or loc["zip"] { known += 1; }
    if citizenship { known += 1; }

    needs_llm = False;
    llm_reason = "";
    # The LLM is consulted only when nothing could be routed. A language
    # outside the lexicon no longer forces it: the narration call writes
    # back in the user's language either way.
    if not top_cat {
        needs_llm = True;
        llm_reason = "no category evidence" if lang else "unrecognized language";
    }

    return {
        "language": lang if lang else "",
        "language_conf": lang_conf,
        "category": top_cat,
        "secondary": secondary,
        "category_scores": scores,
        "category_conf": cat_conf,
        "urgency": urgency,
        "income_annual": income_annual,
        "household_size": household,
        "age": age,
        "state": loc["state"],
        "city": loc["city"],
        "zip": loc["zip"],
        "citizenship": citizenship,
        "flags": flags,
        "evidence": evidence,
        "completeness": round(known / 5.0, 2),
        "needs_llm": needs_llm,
        "llm_reason": llm_reason
    };
}
