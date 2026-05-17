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
import from walkers.translate { TranslateWalker }
