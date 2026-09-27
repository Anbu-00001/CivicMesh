"""NarrateWalker — the turn's one LLM call, deliberately off the critical path.

The client renders IntakeWalker's deterministic answer immediately, then calls
this walker in the background. It asks the model for a warm, localized
two-to-three sentence summary of facts the engine already computed, and
translates the follow-up chips. If the model is slow or down, the user never
notices: the deterministic answer is already on screen.

Guardrail: the narration must not introduce phone numbers the engine didn't
produce. Any digit run of 3+ that isn't in the fact sheet voids the output.
"""

import re;
import time;
import from llm.stubs { narrate_turn, pool_model_names }

"""True if the text contains a 3+ digit run that the facts don't contain."""
def invents_numbers(text: str, facts: str) -> bool {
    fact_digits = set(re.findall(r"\d{3,}", facts.replace("-", "")));
    for d in re.findall(r"\d{3,}", text.replace("-", "")) {
        if d not in fact_digits {
            return True;
        }
    }
    return False;
}

walker NarrateWalker {
    has user_message: str = "";
    has language: str = "en";
    has facts: str = "";
    has chips: list = [];
    has summary: dict = {};

    can narrate with `Root entry {
        t0 = time.perf_counter();
        models = pool_model_names();
        out: dict = {"ok": False, "message": "", "chips": list(self.chips), "models": models};
        try {
            n = narrate_turn(
                user_message=str(self.user_message)[:600],
                language=str(self.language or "en"),
                facts=str(self.facts)[:2000],
                chips=[str(c) for c in self.chips]
            );
            msg = str(n.message).strip();
            chips = [str(c) for c in list(n.chips)];
            if msg and not invents_numbers(msg, str(self.facts)) {
                out["ok"] = True;
                out["message"] = msg;
            } else {
                out["error"] = "guardrail: narration introduced facts not in the engine output" if msg else "empty narration";
            }
            if len(chips) == len(self.chips) {
                out["chips"] = chips;
            }
        } except Exception as ex {
            out["error"] = type(ex).__name__ + ": " + str(ex)[:160];
        }
        out["latency_ms"] = round((time.perf_counter() - t0) * 1000.0, 1);
        self.summary = out;
        report out;
    }
}

sem NarrateWalker is "Background LLM narration: localizes and warms up the deterministic answer; guarded against invented numbers.";
