# platform/app

The composition package; only `cmd/*` imports it. `boot` (the CLI short-circuits, the open-file limit, logs, the
guard, the platform's env), `check` (the boot checks of §6.1, then `--features`, `--routes`, `--limits`), `serve`,
`wait`, `shutdown` and `exit`, and `front`, the request path every request goes through (PLAN §8.4). It imports the
`identity:` family and `store:.` for the family's name. Layer L4 (PLAN §5.1).

Audited: d136601 2026-10-30 docs/audit/M4.md (its M4 diff); 5c5ebf2 2026-10-27 docs/audit/M2.md
