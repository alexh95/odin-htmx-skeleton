# platform/authz/anonymous

The default member of the `identity:` family: everyone is the Guest. Nothing reads or sets a cookie, its CLI
answers nothing and it has no routes; `minimal` and `skeleton` build with it. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
