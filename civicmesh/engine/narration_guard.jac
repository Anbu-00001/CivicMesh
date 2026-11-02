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

"""True when `text` names a program the facts don't, or makes a promise."""
def invents_claims(text: str, facts: str) -> bool {
    known = str(facts).lower();
    for name in re.findall(PROGRAM_NAMES, str(text)) {
        if name.lower() not in known { return True; }
    }
    # "If you qualify, you will receive a card": a condition, not a promise.
    for sent in re.split("[.!?\\n]+", str(text)) {
        if re.search(PROMISES, sent) and not re.search("(?i)\\b(?:if|once|when|si|cuando)\\b", sent) { return True; }
    }
    return False;
}
