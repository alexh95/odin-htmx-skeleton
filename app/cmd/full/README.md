# cmd/full

Houston (PLAN §7.1, §7.3), growing through M4. At slice 3 it is the main host alone: `home` (the root), `about`, `audit`
(`/admin/audit`, M4 slice 4) and `accounts` with its `identity_accounts` (usernames, argon2id passwords, server-side sessions in the `sid` cookie), on
SQLite, the hyperscript client and the full theme. The lab host (`houston-lab`, every starter demo and lab page) and
the rest of the catalog arrive with slice 10. A profile (PLAN §7).
