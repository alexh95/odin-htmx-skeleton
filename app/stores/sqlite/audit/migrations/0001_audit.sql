-- audit's first migration (PLAN §11.5, §17.7). Never edit it once a database has applied it
-- (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS. Times are unix
-- ms. The log is append-only: no row changes, and a row goes only once it is 400 days old.
CREATE TABLE audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  at          INTEGER NOT NULL,
  actor_id    INTEGER NOT NULL,
  actor_name  TEXT NOT NULL,
  action      TEXT NOT NULL,
  target_kind TEXT NOT NULL,
  target_id   INTEGER NOT NULL,
  reason      TEXT NOT NULL,
  client_id   TEXT NOT NULL,
  meta        TEXT NOT NULL
);
CREATE INDEX audit_log_at ON audit_log(at);

CREATE TRIGGER audit_log_no_update BEFORE UPDATE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'audit_log is append-only');
END;

CREATE TRIGGER audit_log_keeps_400_days BEFORE DELETE ON audit_log
WHEN old.at > CAST(unixepoch('subsec') * 1000 AS INTEGER) - 400 * 86400000
BEGIN
  SELECT RAISE(ABORT, 'audit_log keeps every entry for 400 days');
END;
