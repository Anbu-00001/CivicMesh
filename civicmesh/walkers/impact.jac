"""ImpactWalker — aggregate stats across the whole graph for the Impact Report tab.

Traverses every PersonNode reachable from `root`, every NeedNode, and every
ApplicationNode they own to build a single dashboard payload:
  - total_users, total_applications, applications_by_status
  - languages_detected with counts
  - need_categories with counts (housing/food/healthcare/legal)
  - approval_rate (applications approved / non-pending applications)
  - top_resource_names with application counts

Demo-grade aggregator only. No LLM call — pure graph traversal so it stays
fast even when called from a public-facing dashboard tab. Spawned from the
ImpactReport React component on mount and on tab switch.
"""

import from graph.nodes { PersonNode, NeedNode, ApplicationNode }
import from graph.edges { applied_to, has_need }


walker ImpactWalker {
    has summary: dict = {};

    can run with `Root entry {
        people = [root --> [?:PersonNode]];

        total_users = len(people);
        languages: dict = {};
        need_categories: dict = {};
        app_status_counts: dict = {
            "pending": 0,
            "applied": 0,
            "approved": 0,
            "denied": 0,
            "withdrawn": 0
        };
        resource_counts: dict = {};
        total_applications = 0;

        for p in people {
            lang = str(p.language) if p.language else "en";
            if lang in languages {
                languages[lang] = int(languages[lang]) + 1;
            } else {
                languages[lang] = 1;
            }

            needs = [p ->:has_need:-> [?:NeedNode]];
            for n in needs {
                cat = str(n.category) if n.category else "unknown";
                if cat in need_categories {
                    need_categories[cat] = int(need_categories[cat]) + 1;
                } else {
                    need_categories[cat] = 1;
                }
            }

            apps = [p ->:applied_to:-> [?:ApplicationNode]];
            for a in apps {
                total_applications = total_applications + 1;
                status = str(a.status) if a.status else "pending";
                if status in app_status_counts {
                    app_status_counts[status] = int(app_status_counts[status]) + 1;
                } else {
                    app_status_counts[status] = 1;
                }
                rname = str(a.resource_name) if a.resource_name else "unknown";
                if rname in resource_counts {
                    resource_counts[rname] = int(resource_counts[rname]) + 1;
                } else {
                    resource_counts[rname] = 1;
                }
            }
        }

        # Approval rate: approved / (approved + denied + applied). Pending
        # applications are excluded because they haven't reached a decision
        # yet, which would unfairly drag the headline number down.
        decided = (int(app_status_counts["approved"])
                 + int(app_status_counts["denied"])
                 + int(app_status_counts["applied"]));
        approved_n = int(app_status_counts["approved"]) + int(app_status_counts["applied"]);
        approval_rate = 0;
        if decided > 0 {
            approval_rate = int((approved_n * 100) / decided);
        }

        # Flatten the language dict into a list of {lang, count} pairs.
        # Plain JS objects aren't iterable on the client, so emitting a
        # list (rather than letting the client iterate a dict's keys)
        # avoids a runtime TypeError there.
        language_pairs: list = [];
        for lk in languages.keys() {
            language_pairs.append({"lang": str(lk), "count": int(languages[lk])});
        }

        # Same flattening for need_categories — emit as a list so the
        # client doesn't need to call Object.keys() on a JSON-deserialized
        # plain object.
        category_pairs: list = [];
        for ck in need_categories.keys() {
            category_pairs.append({"category": str(ck), "count": int(need_categories[ck])});
        }

        # Pull the top 5 resources by application count for the bar chart.
        resource_pairs: list = [];
        for k in resource_counts.keys() {
            resource_pairs.append({"name": str(k), "count": int(resource_counts[k])});
        }
        # Simple in-place descending sort by count.
        n_pairs = len(resource_pairs);
        i = 0;
        while i < n_pairs {
            j = i + 1;
            while j < n_pairs {
                if int(resource_pairs[j]["count"]) > int(resource_pairs[i]["count"]) {
                    tmp = resource_pairs[i];
                    resource_pairs[i] = resource_pairs[j];
                    resource_pairs[j] = tmp;
                }
                j = j + 1;
            }
            i = i + 1;
        }
        top_resources = resource_pairs[:5] if len(resource_pairs) > 5 else resource_pairs;

        payload = {
            "total_users": total_users,
            "total_applications": total_applications,
            "languages": language_pairs,
            "need_categories": category_pairs,
            "app_status_counts": app_status_counts,
            "approval_rate": approval_rate,
            "top_resources": top_resources
        };
        self.summary = payload;
        report payload;
    }
}

sem ImpactWalker is "Aggregates outcome metrics across every PersonNode + ApplicationNode reachable from root. Pure graph traversal — no LLM call — so the Impact dashboard tab refreshes cheaply on every mount.";
sem ImpactWalker.summary is "Mirror of the final report payload. Sibling walkers spawning this one read it via .summary because `report` only bubbles to the outermost walker.";
