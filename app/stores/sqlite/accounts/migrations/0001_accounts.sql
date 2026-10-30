-- accounts' first migration (PLAN §11.2, §17.1). Never edit it once a database has applied
-- it (the boot refuses a changed hash): add 0002_*.sql and list it in MIGRATIONS. Times are
-- unix ms; users and sessions keep the names D16 gives them.
CREATE TABLE users (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display       TEXT NOT NULL,
  pw_hash       TEXT NOT NULL,
  role          INTEGER NOT NULL,          -- authz.Role: 0 Guest, 1 User, 2 Mod, 3 Admin
  disabled_at   INTEGER NOT NULL DEFAULT 0,
  totp_secret   TEXT NOT NULL DEFAULT '',
  failed_logins INTEGER NOT NULL DEFAULT 0,
  backoff_until INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,             -- hex SHA-256 of the cookie's token, never the token
  user_id    INTEGER NOT NULL REFERENCES users(id),
  created_at INTEGER NOT NULL,
  last_seen  INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  step_up_at INTEGER NOT NULL DEFAULT 0,
  client_id  TEXT NOT NULL DEFAULT ''
) WITHOUT ROWID;
CREATE INDEX sessions_user ON sessions(user_id);

CREATE TABLE accounts_invites (
  code_hash  TEXT PRIMARY KEY,
  role       INTEGER NOT NULL,
  max_uses   INTEGER NOT NULL,
  uses       INTEGER NOT NULL DEFAULT 0,
  created_by INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
) WITHOUT ROWID;

CREATE TABLE accounts_recovery_codes (
  user_id   INTEGER NOT NULL REFERENCES users(id),
  code_hash TEXT NOT NULL,
  used_at   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, code_hash)
) WITHOUT ROWID;

CREATE TABLE accounts_prefs (
  user_id INTEGER NOT NULL REFERENCES users(id),
  key     TEXT NOT NULL,
  value   TEXT NOT NULL,
  PRIMARY KEY (user_id, key)
) WITHOUT ROWID;
