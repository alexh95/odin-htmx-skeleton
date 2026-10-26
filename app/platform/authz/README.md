# platform/authz

Who may do what (D35, PLAN §17.1): one closed `Perm` enum grouped by feature, one `ROLE_PERMS` table, the `Viewer`
the build's identity loads, and the contract an identity implements. A route row names the perm it needs and
`front` checks it before the body is read. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
