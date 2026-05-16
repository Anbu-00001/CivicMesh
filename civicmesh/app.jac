"""CivicMesh — entry point.

The `cl { ... }` block is the client UI shell — it just imports `ClientApp`
from `frontend.cl.jac` and renders it. The real UI lives there.

Server-side walker registration is handled by the companion variant file
`app.sv.jac`. Jac's variant loader merges that file into the server build
automatically, while the client build skips it entirely — so the walker
classes never leak into the browser JS bundle.
"""

cl {
    import from .frontend { ClientApp }

    def:pub app -> JsxElement {
        return <ClientApp/>;
    }
}
