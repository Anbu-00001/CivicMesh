"""LocalizeWalker — translates the engine's full answer, after it is on screen.

Called by the client for languages other than English and Spanish (Spanish
answers are composed natively). Riva Translate first, Gemma 4 for the long
tail; numbers guarded. See llm/translate.jac.
"""

import from llm.translate { translate_text }
import from engine.i18n { language_info }

walker LocalizeWalker {
    has text: str = "";
    has language: str = "";
    has summary: dict = {};

    can localize with `Root entry {
        info = language_info(str(self.language));
        res = translate_text(str(self.text)[:4000], str(self.language));
        out = {
            "ok": bool(res["ok"]), "text": str(res["text"]), "model": str(res["model"]),
            "latency_ms": res.get("latency_ms", 0.0), "error": str(res.get("error", "")),
            "language": str(self.language), "language_name": str(info["name"]), "endonym": str(info["endonym"]), "tier": str(info["tier"])
        };
        self.summary = out;
        report out;
    }
}

sem LocalizeWalker is "Translates the engine's full English answer into the user's language (Riva Translate v2 for its 36 languages, Gemma 4 otherwise), guarded against changed numbers.";
