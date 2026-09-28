"""EscalationWalker — deterministic crisis routing.

Fires when nothing credible matched, when the message shows self-harm or
domestic-violence risk, or when MemoryWalker sees every application denied.
The lead line is chosen in code (a self-harm message must get 988 first,
every time), crisis resources come from the live graph, and there is no LLM
on this path — a crisis reply can't wait on, or be improvised by, a model.
"""

import from graph.nodes { PersonNode, ResourceNode }
import from llm.stubs { EscalationContext }
import from engine.compose { span_begin, span_end }
import from engine.messages { msg, has_messages }
import from engine.i18n { language_info }

glob LEADS: dict = {
    "self_harm": ("988 Suicide and Crisis Lifeline", "988", "free, 24/7, confidential crisis counseling", "consejería de crisis gratuita, 24/7 y confidencial"),
    "dv": ("National Domestic Violence Hotline", "1-800-799-7233", "24/7 safety planning and emergency shelter placement", "planificación de seguridad y refugio de emergencia 24/7"),
    "food": ("2-1-1", "211", "nearest food bank, pantry and SNAP office", "banco de comida, despensa y oficina de SNAP más cercanos"),
    "housing": ("2-1-1", "211", "same-night shelter placement and rental help referrals", "refugio para esta noche y ayuda con la renta"),
    "healthcare": ("2-1-1", "211", "sliding-scale clinics and Medicaid enrollment", "clínicas de pago según ingresos e inscripción en Medicaid"),
    "legal": ("Legal Services Corporation", "1-800-815-9614", "free civil legal aid near you", "asistencia legal civil gratuita cerca de usted")
};

walker EscalationWalker {
    has category: str = "";
    has flags: list = [];
    has language: str = "en";
    has ranked: list = [];
    # Kept for MemoryWalker's all-denied path.
    has context: EscalationContext = EscalationContext();
    has trace: dict = {};
    has parent_span: str = "";
    has summary: dict = {};

    can escalate with PersonNode entry {
        sp = span_begin(self.trace, "EscalationWalker crisis_route", "INTERNAL", self.parent_span, {"gen_ai.agent.name": "EscalationWalker"}) if self.trace else {};
        cat = self.category if self.category else str(self.context.profile.category);
        flags = list(self.flags);
        key = "self_harm" if "self_harm" in flags else ("dv" if "dv" in flags else (cat if cat in LEADS else "housing"));
        lead = LEADS[key];
        es = self.language == "es";
        lead_line = ("Llame a " if es else "Call ") + lead[0] + ": " + lead[1] + " — " + (lead[3] if es else lead[2]) + ".";
        lead_line_en = "";
        if self.language == "es" {
            lead_line_en = msg("en", "esc.call", {"name": lead[0], "phone": lead[1], "what": msg("en", "esc." + key)});
        }
        if self.language not in ["en", "es"] and has_messages(self.language) {
            lead_line = msg(self.language, "esc.call", {"name": lead[0], "phone": lead[1], "what": msg(self.language, "esc." + key)});
            # 988 and the DV hotline interpret 200+ languages for free
            # (988lifeline.org/interpretation-services; thehotline.org).
            if key in ["self_harm", "dv"] {
                lead_line = lead_line + " " + msg(self.language, "esc.interp", {"language": str(language_info(self.language)["name"])});
            }
            # The English original rides along: the number and instructions of
            # a crisis line must be checkable by anyone who reads English.
            lead_line_en = msg("en", "esc.call", {"name": lead[0], "phone": lead[1], "what": msg("en", "esc." + key)});
            if key in ["self_harm", "dv"] {
                lead_line_en = lead_line_en + " " + msg("en", "esc.interp", {"language": str(language_info(self.language)["name"])});
            }
        }

        crisis: list = [];
        for r in [root --> [?:ResourceNode]] {
            if str(r.capacity) == "closed" { continue; }
            name = str(r.agency_name);
            low = name.lower();
            relevant = ("hotline" in low or "lifeline" in low or "helpline" in low) or (str(r.category) == cat and str(r.capacity) == "open");
            if relevant {
                crisis.append({"name": name, "phone": str(r.contact_phone), "category": str(r.category)});
            }
        }
        crisis.sort(key=lambda c: dict : (0 if ("hotline" in c["name"].lower() or "lifeline" in c["name"].lower()) else 1, c["name"]));
        near = [s["resource_name"] + ": " + str(s["counterfactual"]) for s in list(self.ranked) if s.get("counterfactual")][:3];

        payload = {
            "type": "escalation_complete",
            "trigger": str(self.context.trigger_reason) if self.context.trigger_reason else ("risk_flag" if key in ["self_harm", "dv"] else "no_credible_match"),
            "is_emergency": key in ["self_harm", "dv"] or "homeless" in flags,
            "lead_line": lead_line,
            "lead_line_en": lead_line_en,
            "personalized_message": lead_line,
            "crisis_resources": [c["name"] + ": " + c["phone"] for c in crisis[:5]],
            "appeal_options": near,
            "language": self.language
        };
        if sp { span_end(self.trace, sp, {"civicmesh.lead": lead[0]}); }
        self.summary = payload;
    }
}

sem EscalationWalker is "Deterministic crisis routing: picks the right 24/7 line in code (988 for self-harm, DV hotline, 211 by category) and lists open crisis resources from the graph.";
