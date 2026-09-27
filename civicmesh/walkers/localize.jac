"""LocalizeWalker — translates the engine's full answer, after it is on screen.

Called by the client for languages other than English and Spanish (Spanish
answers are composed natively). Riva Translate first, Gemma 4 for the long
tail; numbers guarded. See llm/translate.jac.
"""

import concurrent.futures;
import from llm.translate { translate_text, translate_strings }
import from engine.i18n { language_info }

glob LOC_POOL: Any = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="cm-loc");

walker LocalizeWalker {
    has text: str = "";
    has language: str = "";
    # Short UI strings: follow-up question, quick-reply labels, chips (order kept).
    has strings: list = [];
    has summary: dict = {};

    can localize with `Root entry {
        info = language_info(str(self.language));
        f_text = LOC_POOL.submit(translate_text, str(self.text)[:4000], str(self.language));
        f_str = LOC_POOL.submit(translate_strings, [str(x)[:300] for x in list(self.strings)[:16]], str(self.language));
        res = f_text.result();
        sres = f_str.result();
        out = {
            "strings": list(sres["strings"]), "strings_translated": int(sres["translated"]), "strings_model": str(sres["model"]),
            "ok": bool(res["ok"]), "text": str(res["text"]), "model": str(res["model"]),
            "latency_ms": res.get("latency_ms", 0.0), "error": str(res.get("error", "")),
            "language": str(self.language), "language_name": str(info["name"]), "endonym": str(info["endonym"]), "tier": str(info["tier"])
        };
        self.summary = out;
        report out;
    }
}

sem LocalizeWalker is "Translates the engine's full English answer into the user's language (Riva Translate v2 for its 36 languages, Gemma 4 otherwise), guarded against changed numbers.";
