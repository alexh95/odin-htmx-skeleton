# stores/sqlite/jobs

The job runs in SQLite (PLAN §15.4, 13 §3.6): `jobs_runs`, one row per run keyed by the boot that ran it and its id in
that boot, its progress, log and how it ended. A queued or running row holds a lease its boot's sync renews; at boot
and every minute after, a queued or running row of another boot whose lease lapsed is marked failed, "interrupted by a
restart". The sync's writes go through `write_now` on the scheduler's thread (it has no loop for a queued write to
answer on); rows that ended more than 30 days ago are pruned. A feature store.

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read)
