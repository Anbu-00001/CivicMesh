"""In-process graph checks for the privacy guarantees (no server, no LLM).

    jac test tests/test_privacy_graph.jac

  · a stored NeedNode holds the scrubbed text ([ssn], [phone]), never the numbers;
  · a crisis turn asks for no narration and makes no model call;
  · ForgetWalker deletes the person, needs, applications and self-critiques
    and leaves the public program data (and other visitors) alone.
"""

import from graph.nodes { PersonNode, NeedNode, ResourceNode, ApplicationNode, SessionInsight }
import from graph.edges { has_need }
import from walkers.intake { IntakeWalker }
import from walkers.seed { SeedWalker }
import from walkers.forget { ForgetWalker }

test "stored_need_is_scrubbed_and_forget_deletes_it" {
    root spawn SeedWalker(user_id="priv_a");
    w = root spawn IntakeWalker(conversation="My SSN is 123-45-6789, call me at 713-555-0199. I need food in Houston", user_id="priv_a");
    r = w.reports[-1];
    assert r["profile"]["category"] == "food";
    assert "[ssn]" in r["privacy"]["redacted"];
    p = [root --> [?:PersonNode, user_id == "priv_a"]][0];
    details = [str(n.details) for n in [p ->:has_need:-> [?:NeedNode]]];
    assert len(details) == 1;
    assert "[ssn]" in details[0] and "[phone]" in details[0];
    assert "6789" not in details[0] and "0199" not in details[0];

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
