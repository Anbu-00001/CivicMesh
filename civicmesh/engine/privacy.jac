"""Privacy guard — what CivicMesh keeps, and what may leave the server.

CivicMesh never asks for a name, Social Security number, A-number, address,
phone number or date of birth, but people type them anyway. Two rules:

  1. Identifiers are replaced with typed placeholders ("[ssn]", "[phone]", …)
     before a message is stored (NeedNode.details) or sent to a hosted model
     (the routing fallback and the background narration). The deterministic
     engine still reads the original text in memory, so eligibility is
     unchanged; only the copies that persist or leave are scrubbed.
  2. A crisis turn (self-harm, domestic violence) is never sent to any model:
     it's answered by fixed code, and the narration is skipped.

The NVIDIA API trial terms (§2.6(a), §4.3) forbid sending personal, health or
government-ID information to the hosted models, so rule 1 is a requirement,
not just good practice. ZIP codes and dollar amounts are kept: they're what
the engine needs and they don't identify a person on their own.
"""

import re;

# Order matters: longer, more specific patterns first (a card number would
# otherwise be read as a phone number plus leftovers).
glob REDACTIONS: list = [
    ["[email]", r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+"],
    ["[ssn]", r"(?<!\d)\d{3}[- ]\d{2}[- ]\d{4}(?!\d)"],
    ["[a-number]", r"(?<![\w])[aA][- #]?(?:\d{3}[- ]?\d{3}[- ]?\d{3}|\d{8,9})(?!\d)"],
    ["[card]", r"(?<!\d)(?:\d[ -]?){13,16}(?!\d)"],
    ["[phone]", r"(?<!\d)(?:\+?1[\s.-]?)?\(?\d{3}\)?[\s.-]?\d{3}[\s.-]?\d{4}(?!\d)"],
    ["[date]", r"(?<!\d)\d{1,2}[/.-]\d{1,2}[/.-](?:19|20)\d{2}(?!\d)"],
    ["[address]", r"(?i)(?<![\d$])\d{1,6}\s+(?:(?!(?:and|or|but|need|needs|a|an|the|to|no|not|i|am|we|have|has|kids?|children|people|persons?|years?|yrs|old|months?|weeks?|days?|dollars?|for|of|in|on|my|our|with|per|at|is|are)\b)[a-z0-9.'-]+\s+){1,3}(?:street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|way|court|ct|place|pl|terrace|circle|highway|hwy)\b\.?(?:\s*(?:apt|apartment|unit|#)\s*[\w-]+)?"],
    ["[address]", r"(?i)(?<![\d$])\d{1,6}\s+(?:calle|avenida|av\.|carrera|camino)\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+(?:\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+)?|\b(?:calle|avenida|av\.|carrera|camino)\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+(?:\s+(?!(?:desde|hace|con|de|del|la|el|los|las|por|para|y|en|mis|mi|sin|hasta|porque|que|a|al|unos?|unas?|dos|tres)\b)[\wÀ-ÿ]+)?\s*(?:#|no\.?|núm\.?)?\s*\d{1,6}\b"],
    ["[number]", r"(?<![\d$])\d{7,}(?!\d)"],
    ["\\1[name]", r"((?:[Mm]y name is|[Mm]i nombre es|[Mm]e llamo|[Jj]e m'appelle|[Mm]eu nome é|[Mm]ein Name ist)\s+)[A-ZÀ-Ý][\w'-]+(?:\s[A-ZÀ-Ý][\w'-]+){0,2}"]
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

"""True when the parsed turn is a crisis that must stay on the server."""
def is_private_turn(flags: list) -> bool {
    f = list(flags or []);
    return "self_harm" in f or "dv" in f;
}
