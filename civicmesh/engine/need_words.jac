"""Everyday words for a need, added after a blind audit (2026-11-02) found plain
requests ("health care", "money", "Can I get Medi-Cal?") routed nowhere. Merged into
CATEGORY_LEXICON in engine/parse.jac. Same form: (pattern, weight).

Plain words weigh little, so a message that names something more specific still
goes there: "I have no money for food" is about food.
"""

glob MEDICAID_BRANDS: str = "medi-?cal|tenncare|soonercare|ahcccs|masshealth|badgercare|apple health|husky health|husky(?= (?:a|b|c|d|plan|insurance|free)\\b)|nj familycare|kancare|mainecare|denalicare|med-?quest|hoosier healthwise|healthy indiana plan|heritage health|mo healthnet|minnesotacare|granite advantage|turquoise care|centennial care|rite care|dr\\.? dynasaur|green mountain care|famis|cover virginia|forwardhealth|equalitycare|peachcare|child health plus|essential plan|oregon health plan|medical assistance";
glob SNAP_BRANDS: str = "calfresh|ebt(?: card)?|basic food|foodshare|3squaresvt|lone star card|link card|bridge card|sun bucks|food (?:assistance|benefits?)|nutrition assistance";

glob EXTRA_NEEDS: dict = {
    "healthcare": [
        ("health ?care", 2.5), ("medical(?! school| student| assistant)", 1.5), ("medicare", 2.5), ("atenci[oó]n m[eé]dica", 2.5),
        ("part d", 2.5), ("extra help for (?:medicare|part d|prescriptions)", 2.5), ("(?:std|sti) test(?:ing|s)?", 2.5), ("birth control", 2.5), ("anticonceptiv\\w*", 2.5), ("indian health", 3.0),
        ("(?:in-?)?home care", 2.0), ("eldercare", 2.5), ("elder abuse", 1.5),
        ("pregnant", 1.0), ("embarazada", 1.0), ("dementia", 1.0), ("alzheimer'?s?", 1.0), ("(?:" + MEDICAID_BRANDS + ")", 3.0)
    ],
    "food": [
        ("(?:" + SNAP_BRANDS + ")", 3.0), ("(?<!postage )(?<!food )stamps", 2.0)
    ],
    "housing": [
        ("fema", 3.0), ("wildfire", 2.5), ("hurricane", 2.5), ("tornado", 2.5), ("earthquake", 2.5), ("hurac[aá]n", 2.5), ("inundaci[oó]n", 2.5),
        ("no heat", 2.5), ("(?:shut(?:ting)?|cut(?:ting)?|turn(?:ing)?)\\s+off\\s+(?:my|our|the)\\s+(?:water|power|electric\\w*|gas|lights|heat)", 2.5), ("shut[- ]?off notice", 2.5),
        ("desaloj\\w*", 2.5), ("echar de (?:mi|la|nuestra) casa", 2.5),
        ("(?:vivo|vivimos|viviendo|dormimos|duermo) en (?:mi|nuestro|el|un) (?:carro|coche|auto)", 3.0), ("(?:live|living|sleep|sleeping) in (?:my|our|the|a) (?:car|truck|van)", 3.0)
    ],
    "legal": [
        ("(?:call(?:ing)?|report(?:ing)?|threaten\\w*)[^.!?]{0,30}\\b(?:ice|immigration|la migra)", 3.0), ("child support", 2.5), ("manutenci[oó]n", 2.5), ("elder abuse", 1.5), ("stealing from (?:my |her |his )?(?:elderly |aging )?(?:mom|mother|dad|father|grandma|grandmother|grandpa|grandfather)", 1.5),
        ("ice (?:came|took|raid(?:ed)?|agents?|detained|arrested|picked|showed|is at|at my|has)", 3.0), ("(?:de|por|con) ice", 2.5), ("la migra", 3.0), ("detained", 2.0),
        ("(?:no|sin) (?:tengo )?papeles", 2.0), ("no papers", 1.5), ("(?:patr[oó]n|jefe)[^.!?]{0,15}no me paga\\w*", 3.0), ("ayuda legal", 2.5),
        ("school[^.!?]{0,40}(?:enroll\\w*|register\\w*|papers)", 2.5), ("enroll\\w*[^.!?]{0,30}school", 2.5), ("escuela[^.!?]{0,40}(?:inscrib\\w*|papeles|matricul\\w*)", 2.5), ("papeles[^.!?]{0,40}escuela", 2.5)
    ],
    "money": [
        ("(?:phone|internet|cell ?phone) bill", 2.5), ("(?:phone|internet) (?:got |was |is )?(?:cut|shut) off", 2.5), ("factura (?:de|del) (?:tel[eé]fono|celular|internet)", 2.5), ("head start", 3.0), ("(?:free )?preschool", 2.0),
        ("money", 1.0), ("cash(?! app)", 1.0), ("dinero", 1.0), ("disability(?! checks?| income| payments?| benefits?)", 1.0), ("can'?t work", 1.5),
        ("(?:need|looking for|find) (?:a |some )?(?:job|work)", 2.0), ("necesito (?:un )?(?:trabajo|empleo)", 2.0), ("(?:pay|afford)(?: all)?(?: of)? (?:my|our|the) bills", 2.0)
    ]
};

# Living in a vehicle is homelessness, in the same words as above.
glob EXTRA_HOMELESS: list = ["(?:vivo|vivimos|viviendo|dormimos|duermo) en (?:mi|nuestro|el|un) (?:carro|coche|auto)", "(?:live|living|sleep|sleeping) in (?:my|our|the|a) (?:car|truck|van)"];

# A program named in the message goes first, even before its other facts are known.
glob NAMED_PROGRAMS: dict = {
    "wic-rule": "\\bwic\\b",
    "sun-bucks-rule": "\\b(?:sun bucks|summer ebt)\\b",
    "fema-rule": "\\bfema\\b",
    "head-start-rule": "\\bhead start\\b",
    "snap-rule": "\\b(?:snap|food stamps|stamps|" + SNAP_BRANDS + ")\\b",
    "medicaid-rule": "\\b(?:medicaid|" + MEDICAID_BRANDS + ")\\b"
};
