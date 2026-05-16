"""Async logic for ActionPlan component."""

impl ActionPlan.loadPlan -> None {
    loading = True;
    try {
        result = await root spawn MemoryWalker(
            user_id=user_id,
            mode="read_session"
        );
        if result.reports {
            data: Any = result.reports[0];
            all_steps: list = [];
            approved_names: list = [];
            pending_names: list = [];
            denied_names: list = [];
            try { approved_names = list(data["approved"]); } except Exception as _ex { approved_names = []; }
            try { pending_names = list(data["pending"]); } except Exception as _ex { pending_names = []; }
            try { denied_names = list(data["denied"]); } except Exception as _ex { denied_names = []; }
            for name in approved_names {
                all_steps = all_steps + [{"name": name, "status": "approved"}];
                done_count = done_count + 1;
            }
            for name in pending_names {
                all_steps = all_steps + [{"name": name, "status": "pending"}];
            }
            for name in denied_names {
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
        await root spawn MemoryWalker(
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
