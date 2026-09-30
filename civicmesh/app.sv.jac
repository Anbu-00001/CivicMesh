"""Server-only variant of app.jac.

The `.sv.jac` extension forces server-context compilation. Importing the
walker classes here ensures jac-scale registers them as HTTP/WebSocket
endpoints at server boot. Jac's variant loader merges this file into the
server build automatically when `app.jac` is the entry — the client build
skips it entirely so none of these walker imports end up in the browser JS
bundle.
"""

# Every walker class and every function in this module's namespace becomes an
# HTTP endpoint (jaclang ModuleIntrospector), so only the eleven walkers the
# browser calls are imported here. Eligibility, Navigation, Escalation,
# Pathfinder and Critique run inside IntakeWalker (walkers/intake.jac imports
# them) and are not reachable from outside. cmguard/gateway.py enforces the
# same list at the front door.
import from walkers.intake { IntakeWalker }
import from walkers.memory { MemoryWalker }
import from walkers.narrate { NarrateWalker }
import from walkers.impact { ImpactWalker }
import from walkers.seed { SeedWalker }
import from walkers.graph_snapshot { GraphSnapshotWalker }
import from walkers.critique { ReflectionReadWalker }
import from walkers.platform { PlatformWalker }
import from walkers.local_help { LocalHelpWalker }
import from walkers.localize { LocalizeWalker }
import from walkers.forget { ForgetWalker }

# Last: every walker module is loaded, so their `report` can stop echoing
# answers (with the user's words in them) into the server logs. The leading
# underscore keeps the helper from being exposed as /function/... .
import from walkers.log_privacy { silence_report_logging as _silence_report_logging }
glob REPORT_LOGGING_SILENCED: int = _silence_report_logging();

# Loopback only when started behind the gateway (cmguard/jacbind.py).
import from cmguard.jacbind { bind_upstream as _bind_upstream }
glob UPSTREAM_BIND: str = _bind_upstream();
