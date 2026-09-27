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
import concurrent.futures;
import litellm;
import from engine.i18n { language_info, ascii_digits, RIVA_CODES }
import from llm.stubs { SDK_RETRIES_PINNED }

# Riva translates one segment per request (a multi-paragraph input came back
# as its first paragraph only), so paragraphs go out in parallel.
glob SEG_POOL: Any = concurrent.futures.ThreadPoolExecutor(max_workers=8, thread_name_prefix="cm-mt");
glob MAX_SEGMENTS: int = 8;

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

"""One chat-completion call; returns stripped text ('' on error)."""
def _call(model: str, messages: list, max_tokens: int = 900) -> str {
    resp = litellm.completion(model=model, messages=messages, temperature=0.1, max_tokens=max_tokens, timeout=TRANSLATE_TIMEOUT_S, max_retries=0);
    txt = str(resp.choices[0].message.content or "").strip();
    return re.sub(r"^<text>\s*|\s*</text>$", "", txt).strip();
}

"""Riva, one segment: system message carries the direction ("en-zh-tw")."""
def _riva_segment(seg: str, riva: str) -> str {
    return _call(RIVA_MODEL, [{"role": "system", "content": "en-" + riva}, {"role": "user", "content": seg}], 600);
}

"""True when `out` carries no 3+ digit number that `src` doesn't."""
def numbers_ok(src: str, out: str) -> bool {
    allowed = number_set(src);
    return len([n for n in number_set(out) if n not in allowed]) == 0;
}

"""Translate English text into `code`. Returns {ok, text, model, latency_ms, error, attempts}.

Riva: every paragraph in parallel, joined back in order. Otherwise (or if
any paragraph fails) one LLM call for the whole text.
"""
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
    riva = str(RIVA_CODES.get(str(code), ""));
    if riva {
        paras = [p.strip() for p in re.split(r"\n\s*\n", src) if p.strip()][:MAX_SEGMENTS];
        futs = [SEG_POOL.submit(_riva_segment, p, riva) for p in paras];
        got: list = [];
        for (i, f) in enumerate(futs) {
            try {
                seg = str(f.result(timeout=TRANSLATE_TIMEOUT_S + 1.0));
                got.append(seg if (seg and numbers_ok(paras[i], seg)) else "");
            } except Exception as ex {
                got.append("");
                out["attempts"].append("riva segment " + str(i) + ": " + type(ex).__name__);
            }
        }
        if got and all([g != "" for g in got]) {
            out["ok"] = True;
            out["text"] = "\n\n".join(got);
            out["model"] = RIVA_MODEL;
        } else {
            out["attempts"].append("riva: " + str(len([g for g in got if g])) + "/" + str(len(got)) + " segments");
        }
    }
    if not out["ok"] {
        prompt = llm_prompt(src, name, str(code));
        for model in [POLYGLOT_TRANSLATE_MODEL, FALLBACK_TRANSLATE_MODEL] {
            if (time.perf_counter() - t0) > TRANSLATE_BUDGET_S { break; }
            try {
                txt = _call(model, [{"role": "user", "content": prompt}], 1400);
                if txt and numbers_ok(src, txt) {
                    out["ok"] = True;
                    out["text"] = txt;
                    out["model"] = model;
                    break;
                }
                out["attempts"].append(model + (": guard" if txt else ": empty"));
            } except Exception as ex {
                out["attempts"].append(model + ": " + type(ex).__name__);
            }
        }
    }
    if not out["ok"] {
        out["error"] = "; ".join(out["attempts"])[:240];
    }
    out["latency_ms"] = round((time.perf_counter() - t0) * 1000.0, 1);
    return out;
}

"""Translate short UI strings (follow-up question, quick replies, chips).

One LLM call with numbered lines (cheap on rate limits), parsed back by
number; any missing or number-changing line falls back to Riva for that
line (if Riva covers the language), else stays English. Order preserved.
"""
def translate_strings(strings: list, code: str) -> dict {
    t0 = time.perf_counter();
    items = [str(x) for x in strings];
    res: dict = {"ok": False, "strings": list(items), "model": "", "translated": 0};
    if not items {
        return res;
    }
    info = language_info(code);
    numbered = "\n".join([str(i + 1) + ". " + items[i] for i in range(len(items))]);
    prompt = (
        "Translate each numbered line from English into " + str(info["name"]) + " (" + str(code) + "). "
        + "Keep the numbering: exactly one output line per input line, same count, same order. "
        + "Keep numbers, dollar amounts and program names (SNAP, WIC, Medicaid, CHIP, Section 8) unchanged. "
        + "These are buttons and questions shown to a person asking for help; keep them short and natural. "
        + "Output only the numbered lines.\n\n" + numbered
    );
    got: dict = {};
    for model in [POLYGLOT_TRANSLATE_MODEL, FALLBACK_TRANSLATE_MODEL] {
        try {
            txt = _call(model, [{"role": "user", "content": prompt}], 700);
            for line in txt.splitlines() {
                m = re.match(r"^\s*(\d+)[\.\)、:]\s*(.+?)\s*$", line);
                if m {
                    i = int(m.group(1)) - 1;
                    if 0 <= i and i < len(items) and numbers_ok(items[i], m.group(2)) { got[i] = m.group(2); }
                }
            }
            if len(got) >= len(items) {
                res["model"] = model;
                break;
            }
        } except Exception as _ex {}
    }
    riva = str(RIVA_CODES.get(str(code), ""));
    missing = [i for i in range(len(items)) if i not in got];
    if missing and riva {
        futs = {i: SEG_POOL.submit(_riva_segment, items[i], riva) for i in missing};
        for (i, f) in futs.items() {
            try {
                seg = str(f.result(timeout=TRANSLATE_TIMEOUT_S + 1.0));
                if seg and numbers_ok(items[i], seg) { got[i] = seg; }
            } except Exception as _ex {}
        }
        if not res["model"] { res["model"] = RIVA_MODEL; }
    }
    res["strings"] = [str(got.get(i, items[i])) for i in range(len(items))];
    res["translated"] = len(got);
    res["ok"] = len(got) > 0;
    res["latency_ms"] = round((time.perf_counter() - t0) * 1000.0, 1);
    return res;
}
