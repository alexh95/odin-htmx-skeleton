# platform/env

The typed environment table (D10, PLAN §8.5). `app.boot` records the platform's rows, each feature's `init` (and
`store_sqlite.init`) its own; every value is parsed once, when recorded, and a bad one stops boot with a message
naming the variable. `NAME_FILE` reads a value from a file. `--limits` and `--features --json` print the table with
secrets masked. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
