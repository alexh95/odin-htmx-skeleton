-- accounts' third migration (M4 slice 6, PLAN §17.1): admin-issued one-time reset codes, stored
-- hashed. One live code per user; a redeemed one keeps its used_at.
CREATE TABLE accounts_reset_codes (
  code_hash  TEXT PRIMARY KEY,
  user_id    INTEGER NOT NULL REFERENCES users(id),
  created_by INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at    INTEGER NOT NULL DEFAULT 0
) WITHOUT ROWID;
CREATE INDEX accounts_reset_codes_user ON accounts_reset_codes(user_id);
