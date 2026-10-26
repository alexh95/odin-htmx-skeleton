-- The notes feature's first migration. Never edit it once a database has applied
-- it (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS.
CREATE TABLE notes (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  body TEXT NOT NULL,
  at   INTEGER NOT NULL   -- unix seconds
);
