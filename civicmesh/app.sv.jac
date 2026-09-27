"""Server-only variant of app.jac.

The `.sv.jac` extension forces server-context compilation. Importing the
walker classes here ensures jac-scale registers them as HTTP/WebSocket
endpoints at server boot. Jac's variant loader merges this file into the
server build automatically when `app.jac` is the entry — the client build
skips it entirely so none of these walker imports end up in the browser JS
bundle.
"""

import from walkers.intake { IntakeWalker }
import from walkers.eligibility { EligibilityWalker }
import from walkers.navigation { NavigationWalker }
import from walkers.memory { MemoryWalker }
import from walkers.escalation { EscalationWalker }
import from walkers.narrate { NarrateWalker }
import from walkers.impact { ImpactWalker }
import from walkers.seed { SeedWalker }
import from walkers.graph_snapshot { GraphSnapshotWalker }
import from walkers.pathfinder { PathfinderWalker }
import from walkers.critique { CritiqueWalker, ReflectionReadWalker }
import from walkers.platform { PlatformWalker }
import from walkers.local_help { LocalHelpWalker }
import from walkers.localize { LocalizeWalker }
import from walkers.forget { ForgetWalker }

# Last: every walker module is loaded, so their `report` can stop echoing
# answers (with the user's words in them) into the server logs.
import from walkers.log_privacy { silence_report_logging }
glob REPORT_LOGGING_SILENCED: int = silence_report_logging();
