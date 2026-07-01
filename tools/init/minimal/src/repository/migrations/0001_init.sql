-- Schema migration #1. Add 0002_*.sql beside this (and register it in
-- repo.odin's MIGRATIONS array) to grow the schema; migrations run in order at
-- boot and are recorded in schema_version.
CREATE TABLE notes (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  body TEXT NOT NULL,
  at   INTEGER NOT NULL   -- unix seconds
);
