"""Full-answer translation — a translation model first, an LLM second.

The narrator writes a short summary; this translates the engine's whole
answer (every program, step and the follow-up question), so a user who reads
no English still gets all of it. Routing by language:

  1. NVIDIA Riva Translate 4B Instruct v2 (NIM) for the 36 languages it was
     trained on (English → es-US, pt-BR, zh-CN/zh-TW, vi, ar, hi, ko, ja, ru,
     uk, fr, pl, tr, th, id, ro, hr, bg, …). Prompted with a direction
     ("en-vi") as the system message, as its model card specifies.
  2. Gemma 4 31B (NIM, pre-trained on 140+ languages) for everything else,
     then Mistral-Nemotron as a last resort.

Translation keeps numbers intact, so a guard rejects any output containing a
3+ digit number (phone, amount, ZIP — compared across scripts) that isn't in
the English source. Plain litellm calls (no JSON schema: translation models
don't do structured output), no SDK retries, per-attempt timeouts and an
overall budget.
"""

import os;
import re;
import time;
import litellm;
import from engine.i18n { language_info, ascii_digits, RIVA_CODES }

glob RIVA_MODEL: str = "nvidia_nim/nvidia/riva-translate-4b-instruct-v2";
glob POLYGLOT_TRANSLATE_MODEL: str = "nvidia_nim/google/gemma-4-31b-it";
glob FALLBACK_TRANSLATE_MODEL: str = "nvidia_nim/mistralai/mistral-nemotron";
glob TRANSLATE_TIMEOUT_S: float = 9.0;
glob TRANSLATE_BUDGET_S: float = 16.0;

"""3+ digit runs after joining separators and mapping other scripts' digits."""
def number_set(t: str) -> set {
    joined = re.sub(r"(?<=\d)(?:\)\s?|[\-\.,])\(?(?=\d)", "", ascii_digits(str(t)));
    return set(re.findall(r"\d{3,}", joined));
}

"""Translation prompt for general LLMs (user turn only: some chat templates reject system roles)."""
def llm_prompt(text: str, name: str, code: str) -> str {
    return (
        "Translate the text below from English into " + name + " (" + code + "). "
        + "Keep every number, phone number, dollar amount and program name (SNAP, WIC, Medicaid, CHIP, Section 8, LIHEAP) exactly as written. "
        + "Keep the paragraph breaks. Output only the translation, nothing else.\n\n<text>\n" + text + "\n</text>"
    );
}

"""Translate English text into `code`. Returns {ok, text, model, latency_ms, error, attempts}."""
def translate_text(text: str, code: str) -> dict {
    t0 = time.perf_counter();
    info = language_info(code);
    name = str(info["name"]);
    src = str(text).replace("**", "").strip();
    out: dict = {"ok": False, "text": "", "model": "", "error": "", "attempts": []};
    if not src {
        out["error"] = "empty text";
        return out;
    }
    plan: list = [];
    riva = str(RIVA_CODES.get(str(code), ""));
    if riva {
        plan.append([RIVA_MODEL, [{"role": "system", "content": "en-" + riva}, {"role": "user", "content": src}]]);
    }
    prompt = llm_prompt(src, name, str(code));
    plan.append([POLYGLOT_TRANSLATE_MODEL, [{"role": "user", "content": prompt}]]);
    plan.append([FALLBACK_TRANSLATE_MODEL, [{"role": "user", "content": prompt}]]);
    allowed = number_set(src);
    for step in plan {
        if (time.perf_counter() - t0) > TRANSLATE_BUDGET_S { break; }
        model = str(step[0]);
        try {
            resp = litellm.completion(model=model, messages=step[1], temperature=0.1, max_tokens=1200, timeout=TRANSLATE_TIMEOUT_S, max_retries=0);
            txt = str(resp.choices[0].message.content or "").strip();
            txt = re.sub(r"^<text>\s*|\s*</text>$", "", txt).strip();
            extra = [n for n in number_set(txt) if n not in allowed];
            if not txt {
                out["attempts"].append(model + ": empty");
            } elif extra {
                out["attempts"].append(model + ": guard (new numbers " + ",".join(extra[:3]) + ")");
            } else {
                out["ok"] = True;
                out["text"] = txt;
                out["model"] = model;
                break;
            }
        } except Exception as ex {
            out["attempts"].append(model + ": " + type(ex).__name__);
        }
    }
    if not out["ok"] {
        out["error"] = "; ".join(out["attempts"])[:240];
    }
    out["latency_ms"] = round((time.perf_counter() - t0) * 1000.0, 1);
    return out;
}
