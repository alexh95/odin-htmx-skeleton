-- accounts' second migration (M4 slice 5, PLAN §17.1): the last TOTP step a code was taken for,
-- so the same code (or an older one) is never taken twice.
ALTER TABLE users ADD COLUMN totp_last_step INTEGER NOT NULL DEFAULT 0;
