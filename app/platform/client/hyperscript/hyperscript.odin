package client_hyperscript

// ---- the client family's hyperscript member (D22, PLAN §12.4) ------------------
//
// Behaviours in _hyperscript 0.9.94 (core only, pinned in app/vendor/hyperscript):
// markup says `_="install Name"` (html.behave writes it), and behaviours._hs
// beside this file defines each one; tools/bundle ships it with each reached
// feature's static/*._hs, and _hyperscript itself, after the htmx bundle. app.js
// beside this file holds the gate: hyperscript initialises an element only when
// its `_` is a lone `install <Name>`, so an injected `_` or `text/hyperscript`
// script never runs (05 §5).

NAME :: "hyperscript"
