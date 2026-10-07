-- Schema migration #1. Add 0002_*.sql beside this (and list it in repo.odin's
-- MIGRATIONS) to grow the schema; migrations run in order at boot, each in a
-- transaction, and schema_version records each one's name and hash. Never edit
-- this file once a database has applied it: the next boot refuses to start.
CREATE TABLE notes (
  id   INTEGER PRIMARY KEY AUTOINCREMENT,
  body TEXT NOT NULL,
  at   INTEGER NOT NULL   -- unix seconds
);
