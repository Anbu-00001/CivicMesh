"""Action-plan sequencing — Smith's weighted-shortest-processing-time rule.

Minimising weighted completion time on a single "machine" (the user's day) is
solved exactly by ordering jobs by w/p descending (Smith, 1956). Here:

    w = urgency × P(eligible) × E[approval] × access      (value of the step)
    p = application minutes + waitlist delay equivalent   (cost of the step)

Crisis lines are pinned first. Documents shared across steps are gathered
once ("bring your photo ID — needed by 3 of 4 steps").
"""

glob URGENCY_W: dict = {"immediate": 3.0, "within_days": 2.0, "within_weeks": 1.0};
glob WAITLIST_MINUTES: float = 240.0;
glob DEADLINE_LABEL: dict = {
    "en": {"rolling": "Apply anytime", "monthly": "Monthly cycle — apply early in the month", "annual": "Annual enrollment window", "one_time": "One-time application", "semester": "Intake each semester"},
    "es": {"rolling": "Puede solicitar en cualquier momento", "monthly": "Ciclo mensual — solicite a principios de mes", "annual": "Periodo anual de inscripción", "one_time": "Solicitud única", "semester": "Admisión cada semestre"}
};

"""Imperative first action for a step, by submission method."""
def action_text(name: str, method: str, phone: str, url: str, lang: str) -> str {
    es = lang == "es";
    if method == "phone" and phone {
        return ("Llame al " + phone) if es else ("Call " + phone);
    }
    if method == "online" and url {
        return "Solicite en línea" if es else "Apply online";
    }
    if method == "in_person" {
        return ("Vaya en persona — llame antes al " + phone) if es else ("Go in person — call " + phone + " first");
    }
    if phone {
        return ("Llame al " + phone) if es else ("Call " + phone);
    }
    return ("Contacte a " + name) if es else ("Contact " + name);
}

"""Build the ordered plan from ranked matches (engine.score output)."""
def build_plan(ranked: list, urgency: str, lang: str, max_steps: int = 4) -> dict {
    uw = float(URGENCY_W.get(urgency, 1.0));
    pool: list = [s for s in ranked if s["tier"] in ["likely", "possible"] or (s["tier"] == "needs_info" and float(s["p_eligible"]) >= 0.5) or s.get("pinned", False)];
    jobs: list = [];
    for s in pool {
        form = s.get("form", {}) or {};
        minutes = float(form.get("estimated_minutes", 30) or 30);
        if s["capacity"] == "waitlist" { minutes += WAITLIST_MINUTES; }
        access = 1.3 if (s["capacity"] == "open" and urgency == "immediate") else 1.0;
        w = uw * float(s["p_eligible"]) * float(s["approval"]["mean"]) * access;
        ratio = w / max(5.0, minutes);
        if s.get("pinned", False) { ratio += 100.0; }
        jobs.append((ratio, s, form, minutes));
    }
    jobs.sort(key=lambda j: tuple : -j[0]);
    jobs = jobs[:max_steps];

    labels = DEADLINE_LABEL.get(lang if lang in ["en", "es"] else "en", DEADLINE_LABEL["en"]);
    steps: list = [];
    doc_count: dict = {};
    total_minutes = 0;
    for (i, j) in enumerate(jobs) {
        s = j[1];
        form = j[2];
        docs = list(form.get("required_documents", []) or []);
        for d in docs {
            doc_count[d] = doc_count.get(d, 0) + 1;
        }
        mins = int(form.get("estimated_minutes", 30) or 30);
        total_minutes += mins;
        steps.append({
            "step_number": i + 1,
            "agency_name": s["resource_name"],
            "action_description": action_text(s["resource_name"], str(form.get("submission_method", "")), s["contact_phone"], s["online_url"], lang),
            "documents_needed": docs,
            "deadline_label": str(labels.get(str(form.get("deadline_type", "rolling")), str(form.get("deadline_type", "")))),
            "contact_info": s["contact_phone"] if s["contact_phone"] else s["contact_email"],
            "estimated_minutes": mins,
            "online_url": s["online_url"] if s["online_url"] else str(form.get("url", "")),
            "tier": s["tier"],
            "p_eligible": s["p_eligible"],
            "approval": s["approval"],
            "priority": round(float(j[0]), 5)
        });
    }
    shared: list = sorted([[d, n] for (d, n) in doc_count.items() if n > 1], key=lambda x: list : -x[1]);
    return {"steps": steps, "shared_documents": shared, "total_minutes": total_minutes};
}
