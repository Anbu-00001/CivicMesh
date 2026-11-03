"""What a model's summary may not say beyond the engine's answer.

walkers/narrate.jac already voids a summary with a number or a link the engine
didn't give. That can't catch a wrong sentence (outside review, 2026-11). No
pattern can catch all of them, and the engine's own answer is on screen first,
so this catches the two kinds that do the most harm:

  * a program the engine never named. Acronyms and program names stay in Latin
    letters in every language (the prompt says so), so this works in all of them.
  * a promise. "You will be approved" and "guaranteed" go further than a
    likelihood, and a person may stop looking for help. English and Spanish only;
    other languages have the program check and the number check.
"""

import re;

glob PROGRAM_NAMES: str = "\\b(?:SNAP|EBT|WIC|TEFAP|CSFP|SFMNP|Medicaid|Medi-Cal|Medicare|CHIP|TANF|CalWORKs|SSI|SSDI|LIHEAP|WAP|WIOA|Section 8|HUD-VASH|Head Start|Pell|EITC|Obamacare|COBRA)\\b";
# "Likely qualify", "may qualify" and "if you qualify" are fine: only the flat claim.
glob PROMISES: str = "(?i)\\bguarantee[ds]?\\b|\\bgarantiz\\w+|\\b(?<!if )(?<!likely )(?<!probably )(?<!may )(?<!might )(?<!could )(?<!whether )(?<!see if )you(?: will| are going to|'ll) (?:definitely |certainly |surely )?(?:be approved|get approved|receive|get the|qualify)\\b|\\byou(?:'re| are) (?:already |now )?(?:approved|guaranteed)\\b|\\byou (?:definitely|certainly|automatically|surely) qualify\\b|\\b(?:usted |t[uú] )?(?:ser[aá]|est[aá]s?) (?:aprobad[oa])\\b|\\bcalifica (?:seguro|sin duda|autom[aá]ticamente)\\b";

# Words that send someone away from help, or toward harm. A voided summary only
# means the engine's own answer stands alone, so this leans toward voiding.
# English and Spanish, like PROMISES (blind audit, 2026-11).
glob HARMFUL: str = "(?i)\\bdo(?:n'?t| not) (?:qualify|call|contact|apply)\\b|\\bno point\\b|\\bstop (?:looking|paying|applying|trying|calling)\\b|\\bignore (?:any|the|this|that|your) (?:\\w+ )?(?:letters?|notices?|deadlines?|summons)\\b|\\b(?:won'?t|will not) get better\\b|\\breports? (?:people|you|them|families) to\\b|\\bdeport(?:ed|ation)?\\b|\\b(?:enter|give|send|share) your (?:social security|ssn|bank|password)|\\b(?:application|claim|request)\\b.{0,30}\\b(?:accepted|approved)\\b|\\bcheck is coming\\b|\\bno (?:califica|llame|tiene sentido)\\b|\\bdeje de (?:buscar|pagar|llamar|solicitar)\\b|\\bdeportad[oa]s?\\b";
# A link read aloud gets past the link check: "evil dot example slash claim".
glob SPOKEN_LINK: str = "(?i)\\b[\\w-]+ dot (?:com|org|net|gov|info|example|io|co)\\b|\\bdot [\\w-]+ slash\\b";
# "The Federal Emergency Cash Grant": a named benefit the engine never gave.
glob NAMED_BENEFIT: str = "\\b[A-Z][a-z]+ (?:Grant|Fund|Voucher|Stipend|Program)s?\\b";
# The prompt asks for a short summary, and the screen is a phone.
glob MAX_SUMMARY_CHARS: int = 1200;

"""True when `text` names a program the facts don't, makes a promise, tells the
person not to seek help, or spells out a link."""
def invents_claims(text: str, facts: str) -> bool {
    known = str(facts).lower();
    if re.search(HARMFUL, str(text)) or re.search(SPOKEN_LINK, str(text)) { return True; }
    for name in re.findall(NAMED_BENEFIT, str(text)) {
        if name.lower().rstrip("s") not in known { return True; }
    }
    for name in re.findall(PROGRAM_NAMES, str(text)) {
        if name.lower() not in known { return True; }
    }
    # "If you qualify, you will receive a card": a condition, not a promise.
    for sent in re.split("[.!?\\n]+", str(text)) {
        if re.search(PROMISES, sent) and not re.search("(?i)\\b(?:if|once|when|si|cuando)\\b", sent) { return True; }
    }
    return False;
}
