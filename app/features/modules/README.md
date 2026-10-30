# modules

`/admin/modules` (`Admin_Modules`, LAN only; PLAN §15.4): what this build is, read-only, since nothing switches at
runtime (Q28). The profile and its family members, the mounted features, every route per host with its permission and
flags, the main bundle's htmx extensions, the env rows (a secret shows only as set or unset), the declared limits, each
module's health and the migrations in force.

It imports no feature (`tools/check imports` holds it to that): everything it shows is the platform's. `platform/app`
fills `web.build` at `app.check`, and the SQLite store lists each `migrate` in `store.in_force`. So it can be mounted
in any profile; `full` mounts it.
