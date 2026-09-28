"""GraphSnapshotWalker — the visitor's real case subgraph for the Graph tab.

Reads what the chat pipeline actually persisted under this visitor's root:

  root ─owns→ PersonNode ─has_need→ latest NeedNode ─eligible_for(tier, p)→
  ResourceNode ─governed_by→ EligibilityRuleNode ─requires_form→ FormNode
  PersonNode ─applied_to→ ApplicationNode (non-archived) ··for··> ResourceNode
  ResourceNode ─leads_to(days, difficulty)→ ResourceNode   (escape routes)
  PersonNode ─reflected_on→ SessionInsight ×N

Nothing is drawn that isn't in the graph: node ids are stable strings, every
node carries the fields a tooltip shows, and every edge its schema label and
payload. Read-only, no LLM; one bounded traversal per call.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, EligibilityRuleNode, FormNode, ApplicationNode, SessionInsight }
import from graph.edges { has_need, eligible_for, governed_by, requires_form, applied_to, leads_to, reflected_on }

"""Short display label: the acronym in parentheses if any, else the first words."""
def short_label(name: str) -> str {
    n = str(name);
    if "(" in n and ")" in n {
        inner = n[n.index("(") + 1:n.index(")")];
        if len(inner) <= 14 and " " not in inner.strip() {
            return inner;
        }
        head = n[:n.index("(")].strip();
        if len(head) <= 14 {
            return head;
        }
    }
    words = n.split();
    out = "";
    for w in words {
        if len(out) + len(w) + 1 > 16 { break; }
        out = (out + " " + w).strip();
    }
    return out if out else n[:16];
}

walker GraphSnapshotWalker {
    has user_id: str = "";
    has max_routes: int = 4;
    has summary: dict = {};

    can snap with `Root entry {
        nodes: list = [{"id": "root", "type": "Root", "label": "root", "tip": "Your private graph root — every visitor gets their own."}];
        edges: list = [];
        counts: dict = {
            "ResourceNode": len([root --> [?:ResourceNode]]),
            "PersonNode": 0, "NeedNode": 0, "ApplicationNode": 0, "SessionInsight": 0, "eligible_for": 0
        };
        persons = [root --> [?:PersonNode, user_id == self.user_id]];
        if not persons {
            self.summary = {"ok": True, "empty": True, "nodes": nodes, "edges": edges, "counts": counts};
            report self.summary;
            return;
        }
        p: PersonNode = persons[0];
        counts["PersonNode"] = 1;
        nodes.append({"id": "person", "type": "PersonNode", "label": "You", "tip": "PersonNode · language " + str(p.language or "en") + (" · household " + str(p.family_size) if int(p.family_size or 0) > 0 else "")});
        edges.append({"src": "root", "tgt": "person", "label": "owns"});

        needs = [p ->:has_need:-> [?:NeedNode]];
        counts["NeedNode"] = len(needs);
        needs.sort(key=lambda n: Any : str(n.created_at), reverse=True);
        shown: dict = {};
        if needs {
            nd: NeedNode = needs[0];
            nodes.append({"id": "need", "type": "NeedNode", "label": str(nd.category), "tip": "Latest need · " + str(nd.category) + " · " + str(nd.urgency).replace("_", " ") + " — what the engine understood: " + str(nd.details)[:110], "sub": str(nd.urgency).replace("_", " ")});
            edges.append({"src": "person", "tgt": "need", "label": "has_need"});
            if len(needs) > 1 {
                nodes.append({"id": "needs_prev", "type": "NeedNode", "label": "+" + str(len(needs) - 1) + " earlier", "tip": str(len(needs) - 1) + " earlier NeedNodes on this PersonNode (one per chat turn).", "dim": True});
                edges.append({"src": "person", "tgt": "needs_prev", "label": "has_need"});
            }
            verdicts = [edge nd ->:eligible_for:->];
            counts["eligible_for"] = len(verdicts);
            verdicts.sort(key=lambda e: Any : int(e.rank));
            for e in verdicts[:6] {
                r: Any = e.__jac__.target.archetype;
                rid = "res:" + str(r.agency_name);
                if rid in shown { continue; }
                shown[rid] = str(r.agency_name);
                ben = int(e.benefit_monthly or 0);
                nodes.append({
                    "id": rid, "type": "ResourceNode", "label": short_label(str(r.agency_name)),
                    "tier": str(e.tier), "p": float(e.p_eligible), "rank": int(e.rank),
                    "tip": str(r.agency_name) + " · " + str(e.tier).replace("_", " ") + " · P(eligible) " + str(int(round(float(e.p_eligible) * 100))) + "%" + (" · ≈ $" + str(ben) + "/mo" if ben > 0 else "") + " · " + str(r.capacity) + (" · " + str(r.contact_phone) if r.contact_phone else "")
                });
                edges.append({"src": "need", "tgt": rid, "label": "eligible_for · " + str(int(round(float(e.p_eligible) * 100))) + "%", "tier": str(e.tier)});
                rules = [r ->:governed_by:-> [?:EligibilityRuleNode]];
                if rules {
                    ru: EligibilityRuleNode = rules[0];
                    ruid = "rule:" + str(ru.rule_id);
                    nodes.append({"id": ruid, "type": "EligibilityRuleNode", "label": "rule", "tip": str(ru.criteria_summary)[:160] + (" · " + str(ru.prior_approvals) + "/" + str(ru.prior_attempts) + " recorded approvals" if int(ru.prior_attempts or 0) > 0 else ""), "parent": rid});
                    edges.append({"src": rid, "tgt": ruid, "label": "governed_by"});
                    forms = [ru ->:requires_form:-> [?:FormNode]];
                    if forms {
                        f: FormNode = forms[0];
                        fid = "form:" + str(f.form_id);
                        nodes.append({"id": fid, "type": "FormNode", "label": "form", "tip": str(f.form_name) + " · " + str(f.estimated_minutes) + " min · " + ", ".join([str(d) for d in list(f.required_documents)][:3]), "parent": rid});
                        edges.append({"src": ruid, "tgt": fid, "label": "requires_form"});
                    }
                }
            }
        }

        # Escape routes: leads_to edges out of the programs on screen.
        routes = 0;
        for (rid, name) in list(shown.items()) {
            src_nodes = [root --> [?:ResourceNode, agency_name == name]];
            if not src_nodes { continue; }
            for le in [edge src_nodes[0] ->:leads_to:->] {
                if routes >= self.max_routes { break; }
                tgt: Any = le.__jac__.target.archetype;
                tid = "res:" + str(tgt.agency_name);
                if tid not in shown {
                    shown[tid] = str(tgt.agency_name);
                    nodes.append({"id": tid, "type": "ResourceNode", "label": short_label(str(tgt.agency_name)), "route": True, "tip": str(tgt.agency_name) + " · reachable via " + short_label(name) + ": " + str(le.transition_reason)});
                }
                edges.append({"src": rid, "tgt": tid, "label": "leads_to · " + str(le.typical_days) + "d · " + str(le.difficulty), "route": True});
                routes += 1;
            }
        }

        apps = [p ->:applied_to:-> [?:ApplicationNode, status != "archived"]];
        counts["ApplicationNode"] = len(apps);
        for (i, a) in enumerate(apps[:5]) {
            aid = "app:" + str(i);
            nodes.append({"id": aid, "type": "ApplicationNode", "label": short_label(str(a.resource_name)), "sub": str(a.status), "tip": "ApplicationNode · " + str(a.resource_name) + " · " + str(a.status) + " · updated " + str(a.updated_at)[:16].replace("T", " "), "status": str(a.status)});
            edges.append({"src": "person", "tgt": aid, "label": "applied_to"});
            target = "res:" + str(a.resource_name);
            if target in shown {
                edges.append({"src": aid, "tgt": target, "label": "for", "dashed": True});
            }
        }
        insights = [p ->:reflected_on:-> [?:SessionInsight]];
        counts["SessionInsight"] = len(insights);
        if insights {
            nodes.append({"id": "insights", "type": "SessionInsight", "label": "×" + str(len(insights)), "tip": str(len(insights)) + " SessionInsight nodes — one self-critique per turn (quality score, walkers that ran, LLM calls made)."});
            edges.append({"src": "person", "tgt": "insights", "label": "reflected_on"});
        }
        self.summary = {"ok": True, "empty": False, "nodes": nodes, "edges": edges, "counts": counts};
        report self.summary;
    }
}

sem GraphSnapshotWalker is "Returns the visitor's persisted case subgraph (person, latest need, scored eligible_for edges, rules, forms, applications, leads_to routes) for the Graph tab. Read-only.";
