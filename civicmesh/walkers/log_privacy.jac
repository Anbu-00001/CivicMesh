"""Keep chat content out of the server logs.

jaclang's `report` statement also prints the reported value to the console
(JacBasics.log_report → console.print). On a server that means every answer —
the user's own words (profile.case_text), income, immigration status, crisis
flags — lands in the container logs, which the host keeps and the Space owner
can read. This module swaps the `log_report` that each loaded module imported
for one that queues the report for the HTTP response exactly as before,
without printing it. Access-log lines (method, path, status) are unchanged.

Set CIVICMESH_LOG_REPORTS=1 to print reports again while debugging locally.
"""

import os;
import sys;
import from jaclang.jac0core { jaclib }
import from jaclang.jac0core.runtime { JacRuntimeInterface }

glob ORIGINAL_REPORT: Any = jaclib.log_report;

"""`report` without the console echo (same queueing as JacBasics.log_report)."""
def quiet_report(expr: Any, custom: bool = False) -> None {
    ctx = JacRuntimeInterface.get_context();
    if custom {
        ctx.custom = expr;
        return;
    }
    call_state = ctx.call_state.get(None);
    if call_state {
        call_state.reports.put_nowait(expr);
    }
}

"""Point every loaded module's `log_report` at quiet_report. Returns how many."""
def silence_report_logging -> int {
    if str(os.environ.get("CIVICMESH_LOG_REPORTS", "")) == "1" {
        return 0;
    }
    n = 0;
    for (name, mod) in list(sys.modules.items()) {
        if mod is not None and getattr(mod, "log_report", None) is ORIGINAL_REPORT {
            setattr(mod, "log_report", quiet_report);
            n += 1;
        }
    }
    return n;
}
