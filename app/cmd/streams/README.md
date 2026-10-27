# cmd/streams

The stream substrate's witness (PLAN §7.1): `home` (the root, a card per feature: the Inbox and the notes), `notes`,
`chat` on its four transports, `notify`, `bot` (its mock), `ops`, `status` and `about`, on the memory store, the
vanilla client and the lite theme, with the `nick` identity and no SQLite library in its build. Its host streams: it
mounts `/events` with chat's, notify's, the bot's and ops's topics, and `/csp-report`. A profile (PLAN §7).

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
