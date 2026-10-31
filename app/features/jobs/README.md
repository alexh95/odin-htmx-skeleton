# jobs

`/admin/jobs` (PLAN §15.4, M5; 13 §3.6): every job a profile mounts and every run of it, live. Packages: `jobs` (the
domain: the sync from `platform/workers` into the store, leases, pruning), `models` (`Run_Row` and the store
contract), `views` and `web`; stores in both families (`stores/sqlite/jobs`, `stores/memory/jobs`).

`platform/workers` runs the mounted `JOBS` rows and keeps each run as data (an id, a state, progress, a 4 KiB log); this
feature reads them (`workers.runs_since`) once a second, on its own `jobs.sync` job, into `jobs_runs`, and publishes
each changed run's row on `jobs.runs` (`.Latest`, keyed by the row's id), so the page upserts it, newest first, and a
viewer who arrives mid-run replays the latest row of each run. workers never calls a feature: this one reads.

A queued or running row holds a 30 s lease, renewed every 10 s while its boot lives; at boot and every minute after, a
queued or running row of another boot whose lease lapsed is marked failed, "interrupted by a restart" (the job runs
again when it is next due: a run isn't resumed). Rows that ended 30 days ago go, hourly. Jobs due every minute or more
often (ops's sampler, the lab's beat, the demo reset's check) show only the runs asked for by hand.

| Route | Perm | What |
|---|---|---|
| `GET /admin/jobs` | `Admin_Jobs`, LAN only | the jobs (every, runs, crashes, last time) with Run now, and the newest 50 runs, live |
| `POST /admin/jobs/run` | `Admin_Jobs`, LAN only, step-up | job (its id): queued for the scheduler's next wake (within a second); a reason by `HX-Prompt`, audited as `jobs.run_now` |
| `POST /admin/jobs/cancel` | `Admin_Jobs`, LAN only, step-up | run (`<boot>-<id>`): a queued run is cancelled at once, a running one when its job next checks; a reason, audited as `jobs.cancel` |
| `GET /admin/jobs/runs/<boot>/<id>/log` | `Admin_Jobs`, LAN only | the run's log as a download: how it went, then what it wrote |

It owns `/admin/jobs`, its own prefix.

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read)
