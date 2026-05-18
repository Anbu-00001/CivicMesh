"""TranslateWalker — batch-translates UI strings into the user's detected language.

Spawned by the chat client after a turn completes. Takes the bot reply +
suggestion chips as a flat list of English strings and the target language
code, returns them in the same order, translated. The walker itself does
nothing graph-y — it's just a thin wrapper around the `translate_batch`
LLM stub so the client can call it via the standard `/walker/...` REST
endpoint that jac-scale auto-registers.
"""

import from llm.stubs { translate_batch }

walker TranslateWalker {
    has texts: list[str];
    has target_language: str;
    # Mirror of the final report so callers spawning this from inside
    # another walker can also read .summary directly.
    has summary: dict = {};

    can run with `Root entry {
        # Empty list or empty/english target → pass through unchanged
        if not self.texts {
            payload = {"translated": [], "language": str(self.target_language)};
            self.summary = payload;
            report payload;
            return;
        }
        tgt = str(self.target_language).strip().lower();
        if tgt == "" or tgt == "en" or tgt == "english" {
            payload = {"translated": list(self.texts), "language": tgt};
            self.summary = payload;
            report payload;
            return;
        }
        # Real translation call. Wrap in a try so a stub failure doesn't
        # nuke the whole turn — the client will fall back to English.
        translated: list[str] = [];
        try {
            translated = translate_batch(
                texts=list(self.texts),
                target_language=str(self.target_language)
            );
        } except Exception as _ex {
            translated = list(self.texts);
        }
        # Defensive: if the LLM returned wrong number of items, fall back
        if len(translated) != len(self.texts) {
            translated = list(self.texts);
        }
        payload = {"translated": translated, "language": tgt};
        self.summary = payload;
        report payload;
    }
}

sem TranslateWalker is "Batch-translates UI strings (bot reply + suggestion chips) into the user's detected language. Thin wrapper around the translate_batch LLM stub so the client can call it as a standard /walker/ REST endpoint.";
sem TranslateWalker.texts is "Flat list of English source strings to translate, in display order. The walker returns translations in the same order so the client can re-zip with UI slots.";
sem TranslateWalker.target_language is "Detected language to translate INTO. ISO 639-1 code preferred ('es', 'ta', 'hi'); 'en' or empty short-circuits the LLM call and returns texts unchanged.";
sem TranslateWalker.summary is "Mirror of the final report payload so callers spawning this walker from inside another can read .summary directly.";
