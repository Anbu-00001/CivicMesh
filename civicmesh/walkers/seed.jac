"""SeedWalker: nothing to do any more.

The catalog is one shared copy in memory (graph/catalog.jac), so a new visitor
writes nothing. This stays because a tab left open across a deploy may still
call it, and the gateway's allowlist names it.
"""

walker SeedWalker {
    has user_id: str = "";
    has seed_demo_apps: bool = False;
    has summary: dict = {};

    can run with `Root entry {
        self.summary = {"ok": True, "inserted": 0, "skipped": 0};
        report self.summary;
    }
}

sem SeedWalker is "Kept for tabs open across a deploy. The program catalog is shared in memory, so there is nothing to seed.";
