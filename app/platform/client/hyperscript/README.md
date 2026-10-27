# platform/client/hyperscript

The client family's second member (D22, PLAN §12.4): behaviours in _hyperscript 0.9.94, core only. Markup says
`_="install Name"` through `html.behave`; `behaviours._hs` here defines the platform's core set (Tabs, Toast,
ResetOnSuccess, Dismiss, SearchBox, RangeFill, RelTime, CopyText), and tools/bundle ships it with each reached
feature's `static/*._hs`, after the htmx bundle and _hyperscript itself. `app.js` holds the gate: an element
initialises only when its `_` is a lone `install <Name>`. `client/core.js` (the theme picker, count-up, the overlay's
Escape) comes first in the profile's app.js, as for the vanilla member. Layer L3 (PLAN §5.1).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
