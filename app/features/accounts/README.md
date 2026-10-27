# accounts

Who is asking (PLAN §17.1, D35). At M2 only its `nick` identity exists (ANSWERS round 9): the rest of the feature,
sessions, passwords, TOTP and `identity_accounts`, arrives at M4.

## identity_nick

`features/accounts/identity_nick` (package `accounts_identity_nick`) is a member of the `identity:` family, chosen by a
profile's `build.*` row (`id=features/accounts/identity_nick`; `streams`). A visitor picks a nickname at `/login` and
keeps it as a signed cookie, `nick=<id>.<name>.<expiry>.<mac>` (HMAC-SHA256, `HttpOnly; SameSite=Lax; Path=/`,
`Secure` over https, 30 days, renewed past half): no account, no password, and a random 53-bit id, so two people may
share a name. What it is worth is decided on each request, from the client's address:

| Client | Role |
|---|---|
| in `ACCOUNTS_NICK_ADMIN_CIDRS` (none by default; the e2e suite sets loopback) | Admin: `/admin/ops` opens |
| in `LAN_CIDRS` (`ACCOUNTS_NICK_FROM=lan`, the default; `all` drops the check) | Member: chat, the bot's members' limits |
| anyone else | Guest, with no `Chat_Read`: chat shows "chat is open on the LAN" |

`ACCOUNTS_NICK_KEY` (or `ACCOUNTS_NICK_KEY_FILE`, at least 32 bytes) signs the cookies; with none, a key is made at
boot and nicknames last until a restart (a warn line says so). `app.boot` calls the identity's `init`.

## Prefixes

| Prefix | Why |
|---|---|
| `/login` | front sends a Guest who lacks a route's perm here (§17.2): the identity's own page, whichever identity runs |
| `/logout` | its pair |
