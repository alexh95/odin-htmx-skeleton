# cmd/streams

The stream substrate's witness (PLAN §7.1): `home` (the root, a card per feature: the Inbox and the notes),
`notes`, `chat` on its four transports, `notify` and `about`, on the memory store, the vanilla client and the lite
theme, with the `nick` identity and no SQLite library in its build. `bot`, `ops` and `status` join it through M2.
Its host streams: it mounts `/events` with chat's and notify's topics, and `/csp-report`. A profile (PLAN §7).
