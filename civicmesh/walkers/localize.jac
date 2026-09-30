"""LocalizeWalker — translates the engine's answer, after it is on screen.

Only for languages without a message catalog (engine/messages.jac): those
with one get the whole answer composed natively and never call this. Riva
Translate first, Gemma 4 for the long tail; numbers guarded. See
llm/translate.jac.
"""

import concurrent.futures;
import from llm.translate { translate_text, translate_strings }
import from engine.i18n { language_info }
import from cmguard.tokens { verify as verify_token, content_hash }
import from cmguard.limits { TokenBuckets }
import from cmguard.redact { redact }
import from cmguard { telemetry }

glob LOC_POOL: Any = concurrent.futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="cm-loc");
# Per visitor, on top of the gateway's limits and the model budget.
glob LOC_PER_VISITOR: Any = TokenBuckets(40, 600);

walker LocalizeWalker {
    has text: str = "";
    has language: str = "";
    # Short UI strings: follow-up question, quick-reply labels, chips (order kept).
    has strings: list = [];
    # Tokens IntakeWalker issued for exactly this text / these strings, for
    # this visitor (cmguard/tokens.py). Without one nothing is translated:
    # this walker used to translate any text anyone sent, on our model quota.
    has text_token: str = "";
    has strings_token: str = "";
    has summary: dict = {};

    can localize with `Root entry {
        info = language_info(str(self.language));
        refused = "";
        if str(self.text).strip() {
            refused = verify_token(str(self.text_token), "loc_text", jid(root), content_hash("loc_text", str(self.text), str(self.language)));
        }
        if not refused and self.strings {
            refused = verify_token(str(self.strings_token), "loc_strings", jid(root), content_hash("loc_strings", [str(x) for x in list(self.strings)], str(self.language)));
        }
        if not refused {
            (ok_rate, _wait) = LOC_PER_VISITOR.take(jid(root));
            if not ok_rate { refused = "translation rate limit"; }
        }
        if refused {
            telemetry.count("rejected:localize:" + refused.replace(" ", "_"));
            self.summary = {"strings": [], "strings_translated": 0, "strings_model": "", "ok": False, "text": "", "model": "",
                            "latency_ms": 0.0, "error": "translation refused: " + refused, "language": str(self.language),
                            "language_name": str(info["name"]), "endonym": str(info["endonym"]), "tier": str(info["tier"])};
            report self.summary;
            return;
        }
        # The client asks for the short strings and the full text in separate
        # calls (strings come back in a few seconds; the text can take longer).
        f_text = LOC_POOL.submit(translate_text, str(self.text)[:4000], str(self.language)) if str(self.text).strip() else None;
        f_str = LOC_POOL.submit(translate_strings, [str(x)[:300] for x in list(self.strings)[:16]], str(self.language)) if self.strings else None;
        res = f_text.result() if f_text else {"ok": False, "text": "", "model": "", "error": "no text"};
        sres = f_str.result() if f_str else {"strings": [], "translated": 0, "model": ""};
        out = {
            "strings": list(sres["strings"]), "strings_translated": int(sres["translated"]), "strings_model": str(sres["model"]),
            "ok": bool(res["ok"]), "text": str(res["text"]), "model": str(res["model"]),
            "latency_ms": res.get("latency_ms", 0.0), "error": redact(str(res.get("error", "")))[:200],
            "language": str(self.language), "language_name": str(info["name"]), "endonym": str(info["endonym"]), "tier": str(info["tier"])
        };
        self.summary = out;
        telemetry.maybe_log(None, "app");
        report out;
    }
}

sem LocalizeWalker is "Translates the engine's full English answer into the user's language (Riva Translate v2 for its 36 languages, Gemma 4 otherwise), guarded against changed numbers.";
