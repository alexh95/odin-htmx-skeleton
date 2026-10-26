# platform/workers

Work off the event loops (S11, D16): `submit(pool, task)` on a loop runs `task.run` on a pool thread inside the
guard and `task.done` back on the submitting loop through `nbio.next_tick`; a full queue answers 503. Also the
scheduler over the mounted `JOBS` rows, one thread waking each second. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
