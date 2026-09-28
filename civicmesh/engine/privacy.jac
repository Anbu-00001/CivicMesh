"""Privacy guard — what CivicMesh keeps, and what may leave the server.

The rules, in order of strength:

  1. The user's words are never stored. NeedNode.details holds the engine's
     reading (need_summary: kind of need, urgency, household, income), not
     the message.
  2. The user's words are never sent to a hosted model by default. The
     narration model gets the engine's answer only (facts_for); the routing
     fallback runs only if an operator sets CIVICMESH_MODEL_READS_MESSAGES=1
     for a model whose terms allow personal data. The NVIDIA API trial terms
     do not: §2.6(a) (no "personal data" or "protected health information")
     and §4.3 (no "personal information relating to an identifiable
     individual, financial, health or governmental information").
  3. A crisis turn (self-harm, domestic violence) is never sent to any model,
     whatever the operator setting.
  4. If an operator does opt in, identifiers are replaced with typed
     placeholders first (redact). This is pattern matching, not a guarantee:
     tests/check_privacy.jac measures what it catches and what it misses,
     which is why rules 1–3 don't depend on it.
"""

import os;
import re;

glob REDACTIONS: list = [
    # Order matters: numbers before names, the "[number]" catch-all after the
    # specific numeric forms. Names need an introduction ("I'm …", "Soy …",
    # "my daughter …", "my landlord …", 我叫…): a bare name is not caught.
    ["[email]", r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"],
    ["[ssn]", r"(?<!\d)\d{3}[- ]\d{2}[- ]\d{4}(?!\d)"],
    ["[a-number]", r"(?<![\w])[aA][- #]?(?:\d{3}[- ]?\d{3}[- ]?\d{3}|\d{8,9})(?!\d)"],
    ["[card]", r"(?<!\d)(?:\d[ -]?){13,16}(?!\d)"],
    ["[phone]", r"\+\d{1,3}[\s.-]?\(?\d{1,4}\)?(?:[\s.-]?\d{2,4}){2,4}(?!\d)"],
    ["[phone]", r"(?<!\d)(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?!\d)"],
    ["[date]", r"(?<!\d)\d{1,2}[/.-]\d{1,2}[/.-](?:19|20)\d{2}(?!\d)"],
    ["[date]", r"(?i)\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}(?:st|nd|rd|th)?,?\s+(?:19|20)\d{2}\b"],
    ["[date]", r"(?i)\b\d{1,2}\s+de\s+(?:enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre)\s+(?:de\s+|del\s+)?(?:19|20)\d{2}\b"],
    ["[address]", r"(?i)(?<![\d$])\d{1,6}\s+(?:(?!(?:and|or|but|need|needs|a|an|the|to|no|not|i|am|we|have|has|kids?|children|people|persons?|years?|yrs|old|months?|weeks?|days?|dollars?|for|of|in|on|my|our|with|per|at|is|are)\b)[a-z0-9.'-]+\s+){1,3}(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|way|court|ct|place|pl|terrace|circle|highway|hwy)\b\.?(?:\s*(?:apt|apartment|unit|#)\s*[\w-]+)?"],
    ["[address]", r"(?i)(?<![\d$])\d{1,6}\s+(?:calle|avenida|av\.|carrera|camino)\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+(?:\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+)?|\b(?:calle|avenida|av\.|carrera|camino)\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+(?:\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+)?\s*(?:#|no\.?|núm\.?)?\s*\d{1,6}\b"],
    ["[address]", r"(?<![\d$])\b\d{1,6}\s+(?:[NSEW]\.?|North|South|East|West)\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+)?(?:\s+(?:St|Street|Ave|Avenue|Rd|Road|Blvd|Dr|Drive|Ln|Lane|Way|Ct|Pl)\b\.?)?"],
    ["[school]", r"[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,3}\s+(?:Elementary|Middle|High|Primary|Junior High|Charter|Academy)(?:\s+School)?\b"],
    ["[number]", r"(?<![\d$])\d{7,}(?!\d)"],
    ["\\1[name]", r"((?:\b[Mm]y name is|\b[Mm]y name'?s|\b[Mm]i nombre es|\b[Mm]e llamo|\b[Jj]e m'appelle|\b[Mm]eu nome é|\b[Mm]ein Name ist|\b[Cc]all me|\bI go by)\s+)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"],
    ["\\1[name]", r"((?:\bI'?m|\bI am|\b[Tt]his is)\s+)(?!(?:Not|Sorry|Pregnant|Disabled|Homeless|Here|From|In|On|At|A|An|The|So|Very|Really|Just|Still|Now|Currently|Living|Looking|Trying|Going|Unemployed|Retired|Single|Married|Divorced|Separated|Widowed|Scared|Afraid|Worried|Desperate|Sick|Out|Hungry|Undocumented|Mexican|American|Chinese|Indian|Muslim|Christian|Catholic|Hispanic|Latino|Latina|Black|White|Asian|Haitian|Cuban|Salvadoran|Guatemalan|Honduran|Venezuelan|Filipino|Vietnamese|Korean|Afghan|Ukrainian|Russian|Arab|African|Native|Jewish)\b)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"],
    ["\\1[name]", r"(\b[Ss]oy\s+)(?!(?:Mexican[oa]|Salvadoreñ[oa]|Guatemaltec[oa]|Hondureñ[oa]|Venezolan[oa]|Cuban[oa]|Colombian[oa]|Dominican[oa]|Puertorriqueñ[oa]|Peruan[oa]|Ecuatorian[oa]|Nicaragüense|Madre|Padre|Mamá|Papá|De|Del|La|El|Una?|Muy)\b)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"],
    ["\\1[name]", r"(\b(?:[Mm]y|[Oo]ur|[Mm]i|[Mm]is)\s+(?:son|daughter|kid|child|baby|boy|girl|husband|wife|partner|mom|mother|dad|father|brother|sister|hij[oa]|espos[oa]|beb[eé])(?:'s name is|,| is named| named| called| se llama| llamad[oa])?\s+)(?!(?:Not|Sorry|Pregnant|Disabled|Homeless|Here|From|In|On|At|A|An|The|So|Very|Really|Just|Still|Now|Currently|Living|Looking|Trying|Going|Unemployed|Retired|Single|Married|Divorced|Separated|Widowed|Scared|Afraid|Worried|Desperate|Sick|Out|Hungry|Undocumented|Mexican|American|Chinese|Indian|Muslim|Christian|Catholic|Hispanic|Latino|Latina|Black|White|Asian|Haitian|Cuban|Salvadoran|Guatemalan|Honduran|Venezuelan|Filipino|Vietnamese|Korean|Afghan|Ukrainian|Russian|Arab|African|Native|Jewish)\b)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"],
    ["\\1[name]", r"(\b(?:landlord|manager|boss|caseworker|case worker|social worker|supervisor|due[ñn]o|casero|jefe)(?:\s+is|\s+named|\s+called|\s+se llama|,)?\s+(?:(?:Mr|Mrs|Ms|Miss|Dr|Sr|Sra)\.?\s+)?)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"],
    ["\\1[name]", r"(\b(?:Mr|Mrs|Ms|Miss|Dr)\.?\s+)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+"],
    ["\\1[name]", r"((?:我叫|我的名字是|我名叫|名字叫)\s*)[一-鿿]{2,4}"],
    ["\\1[name]", r"((?:제 이름은)\s*)[가-힣]{2,4}(?=\s*(?:입니다|이에요|예요|이고|이며|,|\.|$))"],
    ["\\1[name]", r"((?:[Tt]ên tôi là|[Tt]ôi tên là)\s+)[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+(?:\s+[A-ZÀ-ÖØ-ÞĐƠƯẠ-Ỹ](?:[^\W\d_]|['’-])+){0,2}"]
];

"""Replace identifiers in `text` with typed placeholders."""
def redact(text: str) -> str {
    out = str(text or "");
    for r in REDACTIONS {
        out = re.sub(r[1], r[0], out);
    }
    return out;
}

"""Placeholder kinds found in `text` (for telemetry — never the values)."""
def redaction_kinds(text: str) -> list {
    t = str(text or "");
    return [r[0].replace("\\1", "") for r in REDACTIONS if re.search(r[1], t)];
}

"""What CivicMesh stores about a need: the engine's reading, never the words.

Kind of need, urgency, household size and income (the last two are what the
engine scores with; PersonNode keeps them too). Immigration status, crisis
flags, location and the message itself are deliberately left out."""
def need_summary(profile: dict) -> str {
    parts: list = [str(profile.get("category", "") or "unrouted"), str(profile.get("urgency", "")).replace("_", " ")];
    hh = int(profile.get("household_size", 0) or 0);
    if hh > 0 { parts.append("household " + str(hh)); }
    inc = int(profile.get("income_annual", -1) if profile.get("income_annual", -1) is not None else -1);
    if inc >= 0 { parts.append("$" + format(inc, ",") + "/yr"); }
    return " · ".join([x for x in parts if x]);
}

"""May the user's message be sent to a hosted model (the routing fallback)?
Only when the operator opts in with CIVICMESH_MODEL_READS_MESSAGES=1, for a
model whose terms allow personal data. Off by default: the NVIDIA API trial
terms forbid sending personal, health or government-ID information."""
def model_may_read_messages -> bool {
    return str(os.environ.get("CIVICMESH_MODEL_READS_MESSAGES", "")).strip() == "1";
}

"""True when the parsed turn is a crisis that must stay on the server."""
def is_private_turn(flags: list) -> bool {
    f = list(flags or []);
    return "self_harm" in f or "dv" in f;
}
