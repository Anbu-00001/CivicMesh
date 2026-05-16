"""Async logic for ActionPlan component."""

impl ActionPlan.loadPlan -> None {
    loading = True;
    try {
        result = root spawn MemoryWalker(
            user_id=user_id,
            mode="read_session"
        );
        data = dict(result.reports[0]) if result.reports else {};
        if data {
            all_steps = [];
            for name in (data.get("approved") or []) {
                all_steps = all_steps + [{"name": name, "status": "approved"}];
                done_count = done_count + 1;
            }
            for name in (data.get("pending") or []) {
                all_steps = all_steps + [{"name": name, "status": "pending"}];
            }
            for name in (data.get("denied") or []) {
                all_steps = all_steps + [{"name": name, "status": "denied"}];
            }
            steps = all_steps;
        }
    } except Exception as _ex {
        steps = [];
    }
    loading = False;
}

impl ActionPlan.markApplied(resource_name: str, idx: int) -> None {
    try {
        root spawn MemoryWalker(
            user_id=user_id,
            mode="update_status",
            resource_name=resource_name,
            new_status="applied"
        );
        # Optimistic update
        steps[idx]["status"] = "applied";
        done_count = done_count + 1;
    } except Exception as _ex {}
}
