# scripting

The nonce class's pages (PLAN §12.2, §12.3, §15.5), on the fixed Scripting bundle (htmx with hx-csp first, hx-live,
sse, ws, hx-multipart and hx-pending) under a per-response nonce CSP with no `'self'`. `/scripting` shows what the
class allows that the hash CSP refuses: a nonced `hx-get` whose answer's own nonce hx-csp rewrites, `hx-on`, a trigger
filter and a `js:` value. `/scripting/live` builds one password-rules widget three ways: `static/scripting.js` (in
app.js), the hyperscript `PasswordRules` behaviour (`static/scripting._hs`; inert on the vanilla client) and hx-live
bindings. `/scripting/streams` sends research 11 §2.2's four buttons over SSE, a WebSocket and multipart (no nonce, the
stream's own, the page's from the connect URL's `pn`, and one handled by a nonced ancestor), and
`streams-hxcsp.spec` pins which work. `/scripting/tt` adds Trusted Types (`.Trusted_Types`) and loads no hyperscript.
Every row is `.Nonce_Csp` and `.Lab_Host`: eval-capable pages never share an origin with sessions (D20). Packages:
`views`, `web`; no store. It owns `/scripting`, its own prefix.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
