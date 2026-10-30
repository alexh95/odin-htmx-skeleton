# platform/authz

Who may do what (D35, PLAN §17.1): one closed `Perm` enum grouped by feature, one `ROLE_PERMS` table, the `Viewer`
the build's identity loads, and the contract an identity implements. A route row names the perm it needs and
`front` checks it before the body is read. Layer L2 (PLAN §5.1).

`refusal` is that check, one pure proc over the viewer, the row's rule (`perm`, `.Lan_Only`, `.Step_Up`), whether the
client is on the LAN and the time: `.Not_Found` off the LAN, `.Sign_In` for a guest without the perm, `.Forbidden`
for anyone else without it, `.Step_Up` for a session whose last password or TOTP check (`Viewer.step_up_at`) is older
than `step_up_window` (10 min; an identity may shorten it at boot) or never happened. `front` answers each (404; 401 with `HX-Redirect` or a 302 to
`/login`, or to `/step-up?next=<path>`; 403); the unit tests hold every answer and the table.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
