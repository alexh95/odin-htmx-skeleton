# platform/html

The page shell and the shared components: the layout, the nav, the theme picker and showroom, toasts, avatars,
badges, written into a `strings.Builder` with every dynamic value through `esc`, `url_encode` or `json_esc`
(re-exported from `platform/escape`). It imports the `client:` and `theme:` families. Layer L3 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
