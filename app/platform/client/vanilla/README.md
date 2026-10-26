# platform/client/vanilla

The `client:` family's vanilla member (D22, PLAN §12.4): `app.js` beside it holds the twins of the platform's
behaviours. `html.behave` writes `data-behave="<name>"` under this member, and one delegated listener per event on
`document` dispatches by that name (and by the theme picker's `data-*`), so swapped-in content needs no wiring and
the CSP needs no inline handler; `htmx:after:process` arms what needs arming (a toast's timer, a range's fill).
`tools/bundle` ships `client/core.js` (the theme picker, count-up, the overlay's Escape: shared with the hyperscript
member) followed by this file as the profile's `app.js`. Layer L3 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
