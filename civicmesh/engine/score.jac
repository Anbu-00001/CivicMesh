"""Explainable eligibility engine — deterministic, calibrated, sub-millisecond.

Replaces one LLM call per resource with closed-form math over the typed graph
data (EligibilityRuleNode fields + resource descriptions):

  * Hard gates (citizenship, age) multiply; soft criteria (income, household,
    residency, situation fit) are a weighted mean. Every criterion reports
    met / unmet / unknown with a plain-language reason.
  * Income uses a logistic "soft threshold"  c = σ(k·(L − I)/L),  k = 6, so
    $50 over a $30k limit reads as borderline rather than a cliff.
  * Unknown ≠ fail: an unknown field contributes its prior expectation and
    lowers *coverage*. Low coverage triggers calibrated abstention — the tier
    becomes "needs_info" instead of a confident guess.
  * Approval odds come from a Beta-Binomial posterior over real outcomes the
    MemoryWalker records (approved / denied), with a capacity-informed prior
    and an 80% UCB exploration bonus for ranking.
  * Counterfactuals: the smallest change that flips a resource to eligible
    ("you'd qualify if yearly income ≤ $30,000 — you're $2,400 over").
  * Value of information: which single unknown fact would move the most
    matches, so the agent asks one sharp question instead of a form.
"""

import math;
import re;

glob INCOME_K: float = 6.0;
glob W_INCOME: float = 0.45;
glob W_SITUATION: float = 0.30;
glob W_RESIDENCY: float = 0.15;
glob W_HOUSEHOLD: float = 0.10;
glob UNKNOWN_HARD: float = 0.7;
glob UNKNOWN_INCOME: float = 0.55;
glob UNKNOWN_RESIDENCY: float = 0.75;

# Capacity-informed Beta prior (pseudo-counts), updated by recorded outcomes.
glob CAPACITY_PRIOR: dict = {"open": [6.0, 3.0], "waitlist": [3.0, 5.0], "closed": [1.0, 6.0]};
glob CAPACITY_FACTOR: dict = {"open": 1.0, "waitlist": 0.72, "closed": 0.3};

# Situation targets, curated per program in data/resources.json
# (eligibility.targets). All listed targets must be evidenced in the user's
# words for a targeted program to count as a fit.
#   target: (user-evidence regex, question key, EN phrase, ES phrase)
glob TARGETS: dict = {
    "homeless": ("homeless|on the street|sleeping in (?:my|our|the|a) car|nowhere to (?:go|stay|sleep)|no place to (?:stay|sleep|live)|shelter tonight|kicked out|sin hogar|en la calle|sin techo|no tenemos d[oó]nde", "homeless", "people who are homeless tonight", "personas sin hogar esta noche"),
    "housing_crisis": ("homeless|on the street|sleeping in (?:my|our|the|a) car|nowhere to|couch|kicked out|evict|losing (?:my|our) (?:home|apartment)|sin hogar|desalo|en la calle", "homeless", "people who are homeless or about to lose housing", "personas sin hogar o a punto de perder su vivienda"),
    "veteran": ("veteran|army|navy|marines?|air force|military|served in|veteran[oa]|ej[eé]rcito", "veteran", "veterans", "veteranos"),
    "disability": ("disabilit|disabled|\\bssi\\b|ssdi|wheelchair|blind|deaf|discapacidad|discapacitad", "disability", "people with a disability", "personas con discapacidad"),
    "dv": ("domestic violence|abus(?:e|ed|ive)|hits me|beats me|hurts me|threatens me|safe house|violencia|maltrat|me golpea|fleeing", "dv", "survivors of domestic violence", "sobrevivientes de violencia doméstica"),
    "hiv": ("\\bhiv\\b|\\baids\\b|\\bvih\\b", "", "people living with HIV", "personas con VIH"),
    "criminal": ("arrested|charged with|criminal case|public defender|\\bjail\\b|court-appointed|arrestad|c[aá]rcel", "", "people facing criminal charges", "personas con cargos penales"),
    "conviction": ("conviction|criminal record|expunge|my record|felony|antecedentes", "", "people with a past conviction", "personas con antecedentes penales"),
    "young_child": ("pregnant|embarazada|\\bbaby\\b|infant|newborn|toddler|beb[eé]|breastfeed|under (?:5|five)", "young_child", "families with a baby, a child under 5, or a pregnancy", "familias con bebé, niño menor de 5 años o embarazo"),
    "children": ("\\bkids?\\b|children|\\bchild\\b|\\bsons?\\b|daughters?|hij[oa]s|ni[nñ][oa]s|teen", "children", "children and teens", "niños y adolescentes"),
    "eviction_risk": ("evict|behind on rent|past due|shut ?off|disconnect|landlord|desalo|atrasad[oa] con la renta|corte de luz", "eviction", "people facing eviction or a utility shutoff", "personas ante desalojo o corte de servicios"),
    "immigration": ("immigra|deport|asylum|visa|green card|citizenship|undocumented|inmigra|asilo|papeles|indocumentad", "", "people with immigration questions", "personas con dudas de inmigración"),
    "crisis": ("suicid|kill myself|end my life|want to die|self[- ]harm|crisis|panic attack|quitarme la vida|no quiero vivir|matarme", "", "people in a mental-health crisis", "personas en crisis de salud mental"),
    "mental_health": ("mental health|depress|anxiety|therapy|therapist|counsel|ptsd|trauma|suicid|salud mental|depresi|ansiedad|terapia", "", "mental-health care needs", "atención de salud mental"),
    "substance": ("drug|alcohol|addict|substance|opioid|overdose|rehab|sober|drogas|adicci", "", "people dealing with substance use", "personas con problemas de consumo de sustancias"),
    "medication": ("medicine|medication|prescription|insulin|pharmacy|\\bmeds\\b|pills|medicina|receta", "", "help paying for medication", "ayuda para pagar medicinas"),
    "dental": ("dental|dentist|tooth|teeth|toothache|muela|diente|dentista", "", "dental care", "atención dental"),
    "vision": ("\\beyes?\\b|vision|glasses|cataract|ojos|vista|lentes", "", "eye care", "atención de la vista"),
    "homebound": ("homebound|can'?t leave (?:the|my) house|bedridden|can'?t cook|can'?t shop|wheelchair|no puedo salir", "", "homebound seniors", "adultos mayores que no pueden salir de casa"),
    "consumer": ("debt collector|credit card|\\bloan|\\bbank\\b|scam|fraud|payday|credit report|cobrador|estafa|pr[eé]stamo", "", "problems with a bank, lender or debt collector", "problemas con un banco, prestamista o cobrador"),
    "energy": ("electric|heating|\\bheat\\b|gas bill|utilit|power bill|power (?:is|was) (?:off|cut)|\\bluz\\b|calefacci|factura de gas", "", "heating or power bills", "facturas de luz o calefacción"),
    "tenant": ("evict|landlord|lease|repairs|\\bmold|\\brent\\b|tenant|desalo|casero|renta|inquilin", "eviction", "renters with landlord problems", "inquilinos con problemas con el casero")
};
glob TARGET_GATE: float = 0.35;

glob QUESTIONS: dict = {
    "en": {
        "income": "About how much does your household earn per month (before taxes)?",
        "household": "How many people live in your household, including you?",
        "age": "How old are you?",
        "citizenship": "Are you a U.S. citizen or permanent resident? (It's okay to say you're not — many programs don't ask.)",
        "location": "What state or city do you live in?",
        "homeless": "Do you have a safe place to sleep tonight?",
        "veteran": "Have you served in the U.S. military?",
        "disability": "Do you or someone in your household have a disability?",
        "dv": "Are you safe at home right now?",
        "young_child": "Is anyone in your household pregnant, or do you have a child under 5?",
        "children": "Do you have children at home?",
        "eviction": "Have you received an eviction notice or are you behind on rent?"
    },
    "es": {
        "income": "¿Cuánto gana su hogar al mes, más o menos (antes de impuestos)?",
        "household": "¿Cuántas personas viven en su hogar, contándose usted?",
        "age": "¿Cuántos años tiene?",
        "citizenship": "¿Es ciudadano/a o residente permanente de EE. UU.? (Está bien decir que no — muchos programas no lo piden.)",
        "location": "¿En qué estado o ciudad vive?",
        "homeless": "¿Tiene un lugar seguro donde dormir esta noche?",
        "veteran": "¿Ha servido en las fuerzas armadas de EE. UU.?",
        "disability": "¿Usted o alguien en su hogar tiene una discapacidad?",
        "dv": "¿Está segura/o en su casa ahora mismo?",
        "young_child": "¿Hay alguien embarazada en su hogar o tiene un niño menor de 5 años?",
        "children": "¿Tiene hijos en casa?",
        "eviction": "¿Recibió un aviso de desalojo o está atrasado/a con la renta?"
    }
};

# ---------- math primitives ----------

"""Logistic function."""
def sigmoid(x: float) -> float {
    if x < -40.0 { return 0.0; }
    if x > 40.0 { return 1.0; }
    return 1.0 / (1.0 + math.exp(-x));
}

"""Beta posterior for approval odds: mean, 90% credible interval, 80% UCB.

Prior pseudo-counts come from capacity (open programs approve more of the
people who reach them); observed approvals/denials from MemoryWalker update it.
The interval uses the normal approximation to the Beta, clipped to [0, 1].
"""
def beta_posterior(approvals: int, attempts: int, capacity: str) -> dict {
    prior = CAPACITY_PRIOR.get(capacity, [2.0, 2.0]);
    wins = max(0, int(approvals));
    losses = max(0, int(attempts) - wins);
    a = float(prior[0]) + wins;
    b = float(prior[1]) + losses;
    n = a + b;
    mean = a / n;
    sd = math.sqrt((a * b) / (n * n * (n + 1.0)));
    return {
        "mean": round(mean, 3),
        "lo": round(max(0.0, mean - 1.645 * sd), 3),
        "hi": round(min(1.0, mean + 1.645 * sd), 3),
        "ucb": round(min(1.0, mean + 1.2816 * sd), 3),
        "alpha": round(a, 2),
        "beta": round(b, 2),
        "observed": wins + losses
    };
}

"""Money formatting for explanations."""
def usd(v: float) -> str {
    return "$" + f"{int(round(v)):,}";
}

# ---------- per-criterion evaluators ----------

"""One criterion record."""
def _crit(key: str, label: str, status: str, score: float, weight: float, hard: bool, detail: str) -> dict {
    return {"key": key, "label": label, "status": status, "score": round(score, 3), "weight": weight, "hard": hard, "detail": detail};
}

"""Localised counterfactual sentence."""
def cf_text(key: str, lang: str, a: str = "", b: str = "") -> str {
    es = lang == "es";
    if key == "income" {
        return ("calificaría si el ingreso anual del hogar fuera de " + a + " o menos (está " + b + " por encima)") if es else ("you'd qualify if yearly household income were " + a + " or less (you're " + b + " over)");
    }
    if key == "citizenship_waiver" {
        return "un estatus migratorio elegible (residencia permanente, refugio o asilo) califica" if es else "an eligible immigration status (green card, refugee or asylee) qualifies";
    }
    if key == "citizenship" {
        return "este programa requiere ciudadanía estadounidense" if es else "this program requires U.S. citizenship";
    }
    if key == "age" {
        return ("está abierto a " + a) if es else ("it's open to " + a);
    }
    if key == "household" {
        return ("requiere un hogar de " + a + " personas o más") if es else ("it needs a household of " + a + " or more");
    }
    if key == "situation" {
        return ("es para " + a + " — dígame si es su caso") if es else ("it's for " + a + " — tell me if that's you");
    }
    return "";
}

"""Score one resource against a parsed profile. Pure function.

resource: {agency_name, category, capacity, description, ...}
rule:     EligibilityRuleNode fields as a dict (incl. curated `targets`)
profile:  engine.parse.parse_intake output (optionally LLM-merged)
message:  raw user text (situation evidence)
"""
def score_resource(resource: dict, rule: dict, profile: dict, message: str, lang: str = "en") -> dict {
    low_msg = str(message).lower();
    flags = list(profile.get("flags", []));
    crits: list = [];
    cfs: list = [];
    asks: list = [];
    gate_extra = 1.0;
    targeted_unconfirmed = False;
    specificity = 1.0;

    income = int(profile.get("income_annual", -1));
    limit = int(rule.get("income_limit_annual", 0) or 0);
    if limit <= 0 {
        crits.append(_crit("income", "Income", "met", 1.0, W_INCOME, False, "No income limit"));
    } elif income < 0 {
        crits.append(_crit("income", "Income", "unknown", UNKNOWN_INCOME, W_INCOME, False, "Limit " + usd(limit) + "/yr — income not mentioned yet"));
        asks.append("income");
    } else {
        c = sigmoid(INCOME_K * (limit - income) / float(limit));
        if income <= limit {
            crits.append(_crit("income", "Income", "met", c, W_INCOME, False, usd(income) + "/yr is under the " + usd(limit) + " limit"));
        } else {
            crits.append(_crit("income", "Income", "unmet", c, W_INCOME, False, usd(income) + "/yr is over the " + usd(limit) + " limit"));
            cfs.append({"key": "income", "effort": (income - limit) / float(limit), "text": cf_text("income", lang, usd(limit), usd(income - limit))});
        }
    }

    if bool(rule.get("citizenship_required", False)) {
        cit = str(profile.get("citizenship", ""));
        waiver = bool(re.search(r"immigra|lpr|refugee|asylee|qualified non-citizen|legal resident", (str(rule.get("exceptions", "")) + " " + str(rule.get("criteria_summary", ""))).lower()));
        if cit == "citizen" or cit == "eligible_immigrant" {
            crits.append(_crit("citizenship", "Status", "met", 1.0, 0.0, True, "Citizen or eligible immigrant"));
        } elif cit == "non_citizen" {
            crits.append(_crit("citizenship", "Status", "unmet", 0.0, 0.0, True, "Needs citizenship or an eligible immigration status"));
            cfs.append({"key": "citizenship", "effort": 2.0, "text": cf_text("citizenship_waiver" if waiver else "citizenship", lang)});
        } else {
            crits.append(_crit("citizenship", "Status", "unknown", UNKNOWN_HARD, 0.0, True, "Citizen or eligible immigrant required"));
            asks.append("citizenship");
        }
    }

    amin = int(rule.get("age_min", 0) or 0);
    amax = int(rule.get("age_max", 0) or 0);
    if amax > 0 and amax <= 19 {
        # Children's program: the age limit applies to the kids, not the parent.
        band = "ages " + str(amin) + "–" + str(amax);
        if "children" in flags or int(profile.get("household_size", 0)) >= 2 and re.search(TARGETS["children"][0], low_msg) {
            crits.append(_crit("age", "Children", "met", 1.0, 0.0, True, "For your children (" + band + ")"));
        } elif int(profile.get("age", 0)) > 0 and int(profile.get("age", 0)) <= amax {
            crits.append(_crit("age", "Age", "met", 1.0, 0.0, True, str(profile.get("age", 0)) + " fits " + band));
        } else {
            crits.append(_crit("age", "Children", "unknown", 0.5, 0.0, True, "For children " + band));
            asks.append("children");
        }
    } elif amin > 0 or amax > 0 {
        age = int(profile.get("age", 0));
        band = ("ages " + str(amin) + "–" + str(amax)) if amax > 0 else ("age " + str(amin) + "+");
        if age > 0 {
            if age >= amin and (amax == 0 or age <= amax) {
                crits.append(_crit("age", "Age", "met", 1.0, 0.0, True, str(age) + " fits " + band));
            } else {
                crits.append(_crit("age", "Age", "unmet", 0.0, 0.0, True, "Open to " + band));
                cfs.append({"key": "age", "effort": 5.0, "text": cf_text("age", lang, band)});
            }
        } elif amin >= 60 and "senior" in flags {
            crits.append(_crit("age", "Age", "met", 0.9, 0.0, True, "Senior (" + band + ")"));
        } elif amin <= 18 {
            crits.append(_crit("age", "Age", "met", 0.95, 0.0, True, "Adults " + band));
        } else {
            crits.append(_crit("age", "Age", "unknown", 0.45, 0.0, True, "Open to " + band));
            asks.append("age");
        }
    }

    minfam = int(rule.get("min_family_size", 0) or 0);
    if minfam > 1 {
        hh = int(profile.get("household_size", 0));
        if hh <= 0 {
            crits.append(_crit("household", "Household", "unknown", 0.5, W_HOUSEHOLD, False, "Needs a household of " + str(minfam) + "+"));
            asks.append("household");
        } elif hh >= minfam {
            crits.append(_crit("household", "Household", "met", 1.0, W_HOUSEHOLD, False, "Household of " + str(hh)));
        } else {
            crits.append(_crit("household", "Household", "unmet", hh / float(minfam), W_HOUSEHOLD, False, "Needs a household of " + str(minfam) + "+"));
            cfs.append({"key": "household", "effort": 4.0, "text": cf_text("household", lang, str(minfam))});
        }
    }

    residency = str(rule.get("residency_requirement", "none") or "none");
    if residency != "none" {
        where = str(profile.get("city", "") or profile.get("state", "") or profile.get("zip", ""));
        if where {
            crits.append(_crit("residency", "Residency", "met", 1.0, W_RESIDENCY, False, residency.title() + " residency — you're in " + where));
        } else {
            crits.append(_crit("residency", "Residency", "unknown", UNKNOWN_RESIDENCY, W_RESIDENCY, False, "Local " + residency + " residency required"));
            asks.append("location");
        }
    }

    targets = [str(t) for t in list(rule.get("targets", []) or []) if str(t) in TARGETS];
    if targets {
        hit: list = [t for t in targets if re.search(TARGETS[t][0], low_msg)];
        miss: list = [t for t in targets if t not in hit];
        es = lang == "es";
        if not miss {
            phrase = ", ".join([TARGETS[t][2] for t in hit]);
            crits.append(_crit("situation", "Situation", "met", 1.0, W_SITUATION, False, "Built for " + phrase));
            # A program designed for exactly this situation beats a general one.
            specificity = 1.3;
        } else {
            t0 = miss[0];
            targeted_unconfirmed = True;
            gate_extra = TARGET_GATE;
            crits.append(_crit("situation", "Situation", "unknown", 0.3, W_SITUATION, False, "Built for " + TARGETS[t0][2]));
            if TARGETS[t0][1] { asks.append(TARGETS[t0][1]); }
            cfs.append({"key": "situation", "effort": 3.0, "text": cf_text("situation", lang, TARGETS[t0][3] if es else TARGETS[t0][2])});
        }
    } else {
        crits.append(_crit("situation", "Situation", "met", 0.85, W_SITUATION, False, "General program — no special situation required"));
    }

    # ---- combine: hard gates multiply, soft criteria average ----
    gate = gate_extra;
    soft_num = 0.0;
    soft_den = 0.0;
    known_w = 0.0;
    total_w = 0.0;
    for c in crits {
        w = 0.25 if c["hard"] else float(c["weight"]);
        total_w += w;
        if c["status"] != "unknown" { known_w += w; }
        if c["hard"] {
            gate = gate * float(c["score"]);
        } else {
            soft_num += float(c["weight"]) * float(c["score"]);
            soft_den += float(c["weight"]);
        }
    }
    p_elig = gate * (soft_num / soft_den if soft_den > 0 else 1.0);
    coverage = known_w / total_w if total_w > 0 else 1.0;
    hard_fail = len([c for c in crits if c["hard"] and c["status"] == "unmet"]) > 0;
    soft_unmet = len([c for c in crits if (not c["hard"]) and c["status"] == "unmet"]);

    # Calibrated abstention: never call a program "likely" on thin evidence.
    if hard_fail or p_elig < 0.2 {
        tier = "unlikely";
    } elif targeted_unconfirmed or (coverage < 0.6 and p_elig >= 0.3) {
        tier = "needs_info";
    } elif p_elig >= 0.65 and soft_unmet == 0 {
        tier = "likely";
    } elif p_elig >= 0.35 {
        tier = "possible";
    } else {
        tier = "unlikely";
    }

    capacity = str(resource.get("capacity", "open"));
    post = beta_posterior(int(rule.get("prior_approvals", 0) or 0), int(rule.get("prior_attempts", 0) or 0), capacity);
    cap_f = float(CAPACITY_FACTOR.get(capacity, 0.6));
    rank = p_elig * cap_f * specificity * (0.55 + 0.45 * float(post["ucb"]));

    cfs.sort(key=lambda c: dict : float(c["effort"]));
    return {
        "resource_name": str(resource.get("agency_name", "")),
        "category": str(resource.get("category", "")),
        "capacity": capacity,
        "p_eligible": round(p_elig, 3),
        "coverage": round(coverage, 2),
        "tier": tier,
        "match_score": int(round(p_elig * 100)),
        "approval": post,
        "rank_score": round(rank, 4),
        "criteria": crits,
        "counterfactual": cfs[0]["text"] if (cfs and tier != "likely") else "",
        "asks": asks,
        "contact_phone": str(resource.get("contact_phone", "")),
        "contact_email": str(resource.get("contact_email", "")),
        "address": str(resource.get("address", "")),
        "online_url": str(resource.get("online_url", "")),
        "description": str(resource.get("description", ""))[:180],
        "languages_supported": list(resource.get("languages_supported", []))
    };
}

"""Category relevance weight for a resource given the parsed need."""
def category_weight(cat: str, profile: dict) -> float {
    if cat == str(profile.get("category", "")) { return 1.0; }
    if cat in list(profile.get("secondary", [])) { return 0.8; }
    return 0.0;
}

"""Score every resource, keep the relevant ones, rank, and pick the next question.

items: [{"resource": {...}, "rule": {...}, "form": {...}}] for the whole graph.
Crisis lines (988, DV hotline) are pinned first when the message shows risk.
"""
def rank_resources(items: list, profile: dict, message: str, limit: int = 6, lang: str = "en") -> dict {
    flags = list(profile.get("flags", []));
    scored: list = [];
    for it in items {
        res = it["resource"];
        cat = str(res.get("category", ""));
        w = category_weight(cat, profile);
        name_low = str(res.get("agency_name", "")).lower();
        pinned = False;
        if "self_harm" in flags and "988" in name_low { pinned = True; }
        if "dv" in flags and "domestic violence" in name_low { pinned = True; }
        if w <= 0.0 and not pinned { continue; }
        s = score_resource(res, it["rule"], profile, message, lang);
        s["form"] = it.get("form", {});
        s["pinned"] = pinned;
        s["rank_score"] = round(float(s["rank_score"]) * (w if w > 0 else 1.0) + (10.0 if pinned else 0.0), 4);
        scored.append(s);
    }
    scored.sort(key=lambda s: dict : -float(s["rank_score"]));

    top = scored[:limit];
    tiers: dict = {"likely": 0, "possible": 0, "needs_info": 0, "unlikely": 0};
    for s in scored {
        tiers[s["tier"]] = tiers[s["tier"]] + 1;
    }

    # Value of information: each unknown fact is worth the rank-weighted
    # eligibility mass it gates among the current top candidates.
    voi: dict = {};
    answered = list(profile.get("answered", []));
    crisis = "self_harm" in flags or "dv" in flags;
    for (i, s) in enumerate(scored[:10]) {
        rw = 1.0 / (1.0 + i);
        if crisis { break; }
        for a in s["asks"] {
            if a in answered { continue; }
            voi[a] = voi.get(a, 0.0) + rw * (1.0 - float(s["coverage"]) + 0.2);
        }
    }
    ask_key = "";
    ask_gain = 0.0;
    for (k, v) in voi.items() {
        if v > ask_gain {
            ask_key = k;
            ask_gain = v;
        }
    }
    affected = len([s for s in scored[:10] if ask_key in s["asks"]]) if ask_key else 0;

    near_misses: list = [s for s in scored if s["tier"] in ["unlikely", "needs_info"] and s["counterfactual"]][:3];
    return {
        "ranked": top,
        "all_count": len(scored),
        "tiers": tiers,
        "near_misses": near_misses,
        "ask": {"key": ask_key, "gain": round(ask_gain, 3), "affects": affected}
    };
}

"""Question text for a value-of-information key in the user's language."""
def question_for(key: str, lang: str) -> str {
    table = QUESTIONS.get(lang if lang in ["en", "es"] else "en", QUESTIONS["en"]);
    return str(table.get(key, ""));
}
