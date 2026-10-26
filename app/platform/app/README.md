# platform/app

The composition package; only `cmd/*` imports it. `boot` (the CLI short-circuits, the open-file limit, logs, the
guard, the platform's env), `check` (the boot checks of §6.1, then `--features`, `--routes`, `--limits`), `serve`,
`wait`, `shutdown` and `exit`, and `front`, the request path every request goes through (PLAN §8.4). It imports the
`identity:` family and `store:.` for the family's name. Layer L4 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
