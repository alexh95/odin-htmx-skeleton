# platform/password

Passwords as argon2id (PLAN §17.1, S0.5, D35): OWASP's parameters (19 MiB, t = 2, p = 1), PHC strings
(`$argon2id$v=19$m=19456,t=2,p=1$<salt>$<tag>`), constant-time compares, and a dummy derive of the same cost for an
unknown name. `hash` and `verify` block for 20–30 ms, so a handler `submit`s a `Verify` to the package's pool
(`start`, `ACCOUNTS_ARGON_THREADS` workers and a queue of 32; past it, 503) and answers from its `done` through a
deferred response. Each worker keeps one buffer for argon's memory: the pool holds threads × 19 MiB and allocates
nothing per login. A stored string may name only these parameters or OWASP's small preset (7 MiB, t = 5), so a
database row can't ask for any cost. `check` is the length rule, 10–256 bytes. Both identities that take a password
use it: `accounts` and `envadmin`. Layer L2 (PLAN §5.1).

Audited: d136601 2026-10-30 docs/audit/M4.md
