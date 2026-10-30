-- jobs' first migration (PLAN §15.4, 13 §3.6). Never edit it once a database has applied it
-- (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS. Times are unix
-- ms. A run is keyed by the boot that ran it and its id in that boot; a queued or running row
-- holds a lease its boot's sync renews.
CREATE TABLE jobs_runs (
  boot        INTEGER NOT NULL,
  id          INTEGER NOT NULL,
  job         TEXT NOT NULL,
  state       TEXT NOT NULL,
  by_hand     INTEGER NOT NULL,
  queued_at   INTEGER NOT NULL,
  started_at  INTEGER NOT NULL,
  ended_at    INTEGER NOT NULL,
  done        INTEGER NOT NULL,
  total       INTEGER NOT NULL,
  log         TEXT NOT NULL,
  note        TEXT NOT NULL,
  lease_until INTEGER NOT NULL,
  PRIMARY KEY (boot, id)
) WITHOUT ROWID;
CREATE INDEX jobs_runs_queued ON jobs_runs(queued_at);
CREATE INDEX jobs_runs_live ON jobs_runs(state, lease_until) WHERE state IN ('queued', 'running');
