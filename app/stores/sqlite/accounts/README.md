# stores/sqlite/accounts

Accounts in SQLite (D18: accounts have no memory member): users, sessions, invites, recovery codes and preferences
(`0001_accounts.sql`; times unix ms). Reads on the loop's reader; every write an op through the writer task. A session
is stored by the SHA-256 of its token, as hex, never the token; a sign-in's session row and the clearing of the user's
failures commit in one op. `features/accounts/storetest` holds it to the contract in `accounts_models`. A feature
store.

Audited: none yet (M4)
