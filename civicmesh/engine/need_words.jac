"""Everyday words for a need, added after a blind audit (2026-11-02) found plain
requests ("health care", "money", "Can I get Medi-Cal?") routed nowhere. Merged into
CATEGORY_LEXICON in engine/parse.jac. Same form: (pattern, weight).

Plain words weigh little, so a message that names something more specific still
goes there: "I have no money for food" is about food.
"""

glob MEDICAID_BRANDS: str = "medi-?cal|tenncare|soonercare|ahcccs|masshealth|badgercare|apple health|husky health|husky(?= (?:a|b|c|d|plan|insurance|free)\\b)|nj familycare|kancare|mainecare|denalicare|med-?quest|hoosier healthwise|healthy indiana plan|heritage health|mo healthnet|minnesotacare|granite advantage|turquoise care|centennial care|rite care|dr\\.? dynasaur|green mountain care|famis|cover virginia|forwardhealth|equalitycare|peachcare|child health plus|essential plan|oregon health plan|medical assistance";
glob SNAP_BRANDS: str = "calfresh|ebt(?: card)?|basic food|foodshare|3squaresvt|lone star card|link card|bridge card|sun bucks|food (?:assistance|benefits?)|nutrition assistance";

# Typed in Latin letters on a phone with no other keyboard (blind audit F22).
# Whole phrases or words unusual in English, so they don't fire on English text.
glob ROMANIZED: dict = {
    "housing": [("thue nha", 2.0), ("tien nha", 2.0), ("khong co nha", 2.0), ("bi duoi", 2.0), ("fang ?zi", 2.0), ("zu ?fang", 2.0), ("fang ?zu", 2.0), ("mei you (?:di fang )?zhu", 2.0), ("sakan", 2.0), ("eskan", 2.0), ("iskan", 2.0), ("el ?ijar", 2.0), ("ijar", 2.0), ("igar", 2.0), ("beit", 2.0)],
    "food": [("thuc an", 2.0), ("mua do an", 2.0), ("mua com", 2.0), ("chi ?fan", 2.0), ("shi ?wu", 2.0), ("mei (?:you )?(?:fan|dong xi) chi", 2.0), ("ta3am", 2.0), ("akl", 2.0), ("ga3an", 2.0), ("ga3ana", 2.0), ("jo3an", 2.0), ("jaw3an", 2.0)],
    "healthcare": [("bac si", 2.0), ("benh vien", 2.0), ("yi ?sheng", 2.0), ("kan ?bing", 2.0), ("yi ?yuan", 2.0), ("doktor", 2.0), ("mostashfa", 2.0), ("mustashfa", 2.0), ("dawa", 2.0)],
    "legal": [("luat su", 2.0), ("lu ?shi", 2.0), ("mohami", 2.0), ("mo7ami", 2.0), ("muhami", 2.0)]
};

glob EXTRA_NEEDS: dict = {
    "healthcare": [
        ("medicade|medicaide|medicad|medi-caid|medicaid", 3.0), ("lost (?:my |our |his |her )?(?:health )?(?:coverage|insurance)", 2.5),
        ("health ?care", 2.5), ("medical(?! school| student| assistant)", 1.5), ("medicare", 2.5), ("atenci[oó]n m[eé]dica", 2.5),
        ("part d", 2.5), ("extra help for (?:medicare|part d|prescriptions)", 2.5), ("(?:std|sti) test(?:ing|s)?", 2.5), ("birth control", 2.5), ("anticonceptiv\\w*", 2.5), ("indian health", 3.0),
        ("(?:in-?)?home care", 2.0), ("eldercare", 2.5), ("elder abuse", 1.5),
        ("pregnant", 1.0), ("embarazada", 1.0), ("dementia", 1.0), ("alzheimer'?s?", 1.0), ("(?:" + MEDICAID_BRANDS + ")", 3.0)
    ],
    "food": [
        ("(?:" + SNAP_BRANDS + ")", 3.0), ("(?<!postage )(?<!food )stamps", 2.0), ("foodstamps", 3.0), ("food ?stamp", 3.0)
    ],
    "housing": [
        ("evicshun|evicion|evition|evictoin", 3.0), ("[357][- ]day notice", 2.5), ("couch[- ]?surf\\w*", 3.0), ("(?:cant|can'?t|cannot) pay (?:my |the |our )?(?:rent|rnt)", 2.5), ("rnt", 1.5),
        ("sec(?:t)?\\.? ?8", 3.0), ("(?:lectric|electric|elec|power) (?:bil|bill)", 2.5),
        ("fema", 3.0), ("wildfire", 2.5), ("hurricane", 2.5), ("tornado", 2.5), ("earthquake", 2.5), ("hurac[aá]n", 2.5), ("inundaci[oó]n", 2.5),
        ("no heat", 2.5), ("(?:shut(?:ting)?|cut(?:ting)?|turn(?:ing)?)\\s+off\\s+(?:my|our|the)\\s+(?:water|power|electric\\w*|gas|lights|heat)", 2.5), ("shut[- ]?off notice", 2.5),
        ("desaloj\\w*", 2.5), ("echar de (?:mi|la|nuestra) casa", 2.5),
        ("(?:vivo|vivimos|viviendo|dormimos|duermo) en (?:mi|nuestro|el|un) (?:carro|coche|auto)", 3.0), ("(?:live|living|sleep|sleeping) in (?:my|our|the|a) (?:car|truck|van)", 3.0)
    ],
    "legal": [
        ("(?:cps|child protective services)[^.!?]{0,30}\\b(?:took|removed|has|have) (?:my|our) (?:kids|children|baby|son|daughter)", 3.0), ("u[- ]?visa", 3.0),
        ("(?:boss|employer|job|company)[^.!?]{0,15}\\b(?:isn'?t|is not|won'?t|hasn'?t|didn'?t|not|never) pa(?:y|id|ying) (?:me|us)", 3.0), ("wage theft", 3.0),
        ("(?:call(?:ing)?|report(?:ing)?|threaten\\w*)[^.!?]{0,30}\\b(?:ice|immigration|la migra)", 3.0), ("child support", 2.5), ("manutenci[oó]n", 2.5), ("elder abuse", 1.5), ("stealing from (?:my |her |his )?(?:elderly |aging )?(?:mom|mother|dad|father|grandma|grandmother|grandpa|grandfather)", 1.5),
        ("ice (?:came|took|raid(?:ed)?|agents?|detained|arrested|picked|showed|is at|at my|has)", 3.0), ("(?:de|por|con) ice", 2.5), ("la migra", 3.0), ("detained", 2.0),
        ("(?:no|sin) (?:tengo )?papeles", 2.0), ("no papers", 1.5), ("(?:patr[oó]n|jefe)[^.!?]{0,15}no me paga\\w*", 3.0), ("ayuda legal", 2.5),
        ("school[^.!?]{0,40}(?:enroll\\w*|register\\w*|papers)", 2.5), ("enroll\\w*[^.!?]{0,30}school", 2.5), ("escuela[^.!?]{0,40}(?:inscrib\\w*|papeles|matricul\\w*)", 2.5), ("papeles[^.!?]{0,40}escuela", 2.5)
    ],
    "money": [
        ("(?:watch|babysit|take care of|look after) (?:my|our) (?:baby|kids?|children|son|daughter|toddler) while i (?:go to |am at |'m at )?work", 3.0),
        ("active[- ]duty", 2.0), ("military (?:family|spouse|wife|husband|member)", 2.0), ("service ?member", 2.0), ("national guard", 2.0), ("(?:husband|wife|spouse) is in the (?:army|navy|marines|air force|coast guard|military)", 2.0),
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
