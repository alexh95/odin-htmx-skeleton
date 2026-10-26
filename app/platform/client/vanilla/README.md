# platform/client/vanilla

The `client:` family's vanilla member (D22): `app.js` beside it routes every click and change through one delegated
listener by `data-*` attributes, so swapped-in content needs no wiring and the CSP needs no inline handler.
`tools/bundle` ships it as the profile's `app.js`. Layer L3 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
