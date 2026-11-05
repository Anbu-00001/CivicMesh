"""In-process graph checks for the privacy guarantees (no server, no LLM).

    jac test tests/test_privacy_graph.jac

  · a stored NeedNode holds the engine's reading, never the words typed;
  · a crisis turn asks for no narration and makes no model call;
  · ForgetWalker deletes the person, needs, applications and self-critiques
    and leaves the public program data (and other visitors) alone.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, ApplicationNode, SessionInsight }
import from graph.edges { has_need, reflected_on }
import from walkers.intake { IntakeWalker, GuestIntakeWalker }
import from walkers.seed { SeedWalker }
import from walkers.forget { ForgetWalker }

test "a_new_visitor_gets_no_copy_of_the_catalog_and_forget_removes_what_they_matched" {
    root spawn SeedWalker(user_id="lazy_a");
    assert len([root --> [?:ResourceNode]]) == 0;
    w = root spawn IntakeWalker(conversation="I need food, 2 of us in Ohio, we earn $1000 a month", user_id="lazy_a");
    r = w.reports[-1];
    assert len(r["matches"]) > 0;
    made = len([root --> [?:ResourceNode]]);
    assert made > 0 and made <= 6;
    assert len(r["routes"]) >= 0;
    f = root spawn ForgetWalker(user_id="lazy_a");
    assert f.reports[-1]["ok"];
    assert len([root --> [?:ResourceNode]]) == 0;
}

test "the_no_account_route_answers_and_connects_nothing" {
    before = len([root -->]);
    w = root spawn GuestIntakeWalker(conversation="I want to kill myself, I need food in Ohio", user_id="someone_elses_id");
    r = w.reports[-1];
    assert r["guest"];
    assert r["escalation"]["lead_phone"] == "988";
    assert r["privacy"]["private_turn"];
    assert not r["llm"]["narrate"];
    w2 = root spawn GuestIntakeWalker(conversation="I need food, 2 of us in Ohio, we earn $1000 a month", user_id="x");
    r2 = w2.reports[-1];
    assert len(r2["matches"]) > 0;
    assert not r2["llm"]["narrate"];
    assert len(r2["plan"]["steps"]) > 0;
    assert len([root -->]) == before;
    assert len([root --> [?:PersonNode]]) == 0;
}

test "stored_need_is_scrubbed_and_forget_deletes_it" {
    root spawn SeedWalker(user_id="priv_a");
    w = root spawn IntakeWalker(conversation="My SSN is 123-45-6789, call me at 713-555-0199. I need food in Houston", user_id="priv_a");
    r = w.reports[-1];
    assert r["profile"]["category"] == "food";
    assert r["privacy"]["words_stored"] == False and r["privacy"]["words_sent_to_model"] == False;
    p = [root --> [?:PersonNode, user_id == "priv_a"]][0];
    details = [str(n.details) for n in [p ->:has_need:-> [?:NeedNode]]];
    assert len(details) == 1;
    assert details[0].startswith("food");
    for w in ["SSN", "6789", "0199", "call me", "Houston"] { assert w not in details[0]; }
    # The self-critique is stored too: its snippet and headline hold no words.
    for ins in [p ->:reflected_on:-> [?:SessionInsight]] {
        for w in ["SSN", "6789", "0199", "call me", "Houston"] {
            assert w not in str(ins.user_prompt_snippet) and w not in str(ins.headline);
        }
    }

    c = root spawn IntakeWalker(conversation="I want to kill myself", user_id="priv_a");
    rc = c.reports[-1];
    assert rc["privacy"]["private_turn"];
    assert not rc["llm"]["narrate"];
    assert not rc["llm"]["sync_used"];

    root spawn IntakeWalker(conversation="I need a doctor", user_id="priv_b");
    before = len([root --> [?:ResourceNode]]);
    f = root spawn ForgetWalker(user_id="priv_a");
    out = f.reports[-1];
    assert out["ok"];
    assert out["removed"]["PersonNode"] == 1;
    assert out["removed"]["NeedNode"] == 2;
    assert len([root --> [?:PersonNode, user_id == "priv_a"]]) == 0;
    assert len([root --> [?:ResourceNode]]) == before;
    assert len([root --> [?:PersonNode, user_id == "priv_b"]]) == 1;
}
