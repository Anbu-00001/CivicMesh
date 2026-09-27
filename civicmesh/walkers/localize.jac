"""LocalizeWalker — translates the engine's answer, after it is on screen.

Only for languages without a message catalog (engine/messages.jac): those
with one get the whole answer composed natively and never call this. Riva
Translate first, Gemma 4 for the long tail; numbers guarded. See
llm/translate.jac.
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
        # The client asks for the short strings and the full text in separate
        # calls (strings come back in a few seconds; the text can take longer).
        f_text = LOC_POOL.submit(translate_text, str(self.text)[:4000], str(self.language)) if str(self.text).strip() else None;
        f_str = LOC_POOL.submit(translate_strings, [str(x)[:300] for x in list(self.strings)[:16]], str(self.language)) if self.strings else None;
        res = f_text.result() if f_text else {"ok": False, "text": "", "model": "", "error": "no text"};
        sres = f_str.result() if f_str else {"strings": [], "translated": 0, "model": ""};
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
