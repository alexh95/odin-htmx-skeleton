# chat

Rooms on the LAN (PLAN §14.1, D30), live over four transports. Packages: `chat` (the domain: bodies of at most 2,000
runes, the 10-minute edit window, room names and slugs, and what lives only in the process whatever the store:
presence, read cursors, the names mentions match), `models` (rooms, messages, the post and change ops, the store
contract), `views` (the rooms, a room, a message, its menu and edit form, presence, typing, unread counts),
`transport_ws`, `transport_sse`, `transport_poll`, `transport_multipart` (each a room's wiring, its endpoint and its
extensions) and `web` (the routes, the topics, the switch, one post path for forms and sockets). Its store at M2:
memory (`app/stores/memory/chat/`); SQLite, DMs, moderation, uploads and search join at M6.

**One fragment for every transport.** A message is rendered once, `<article id="m-<id>">`, and travels as
`<hx-partial hx-target="#log-<room>" hx-swap="upsert sort">`: upsert replaces what the log already has (an edit, a
tombstone, a reconnect's snapshot, the author's own reply and the hub's copy of it) and sorts a new one in by id, so
nothing doubles. What differs per viewer is asked for (the menu, `GET /chat/m/<id>/menu`) or marked on the client
(`AutoScroll` sets `.mine` where `data-author` is the log's `data-me`).

| Transport | The pane | The composer | A reconnect |
|---|---|---|---|
| `ws` (default) | `hx-ws:connect` `/chat/r/<slug>/ws` | `hx-ws:send` (JSON `{body}`) | the last 50 again |
| `sse` | the room's topic on the layout's `#live` | `hx-post`, `hx-pending` | the hub's ring, else `resync` → `/since` |
| `poll` | `hx-get` `/chat/r/<slug>/since` every 2 s, `hx-ptag` | `hx-post`, `hx-pending` | the tag: what changed since it |
| `multipart` | `hx-multipart:connect` `/chat/r/<slug>/parts` | `hx-post`, `hx-pending` | what came after `HX-Last-Part-ID` |

The choice is per request: `?transport=`, the member's Connection setting (the `chat_transport` cookie, from
`POST /chat/transport`), else `CHAT_TRANSPORT`; the response says which in `x-impl: chat.transport=<t>`.

**Every page of a room** also carries `chat.presence:<id>` and `chat.typing:<id>` on its `#live`: presence learns who is
there from those streams opening and closing (the hub's `watch` hook: online at once, away 10 s after the last closed,
gone after 5 minutes, published by the `chat.presence` job), and typing is `POST /chat/r/<slug>/typing` from the
composer (`throttle:2s`), upserted and faded by CSS (`Expire` removes it on the hyperscript client). The newest message
a page renders or receives posts a read receipt when it scrolls into view (`hx-trigger="intersect once"`, never a GET);
a new message moves every other reader's unread count on `.unread-<slug>`, through their `notify.user` topic, and a
mention (`@name`, the name a member last used here) lands in their Inbox through `notify_web.send`.

**Limits** (§17.5): posts 5 per 10 s per member (`web.Limit`, a 429 with `Retry-After` into the toasts; a socket gets
the toast down the socket), typing 1 per 2 s (the rest dropped), socket frames 20 a second (then 1008), bodies 2,000
runes, 100 rooms in a memory build, at most 4,096 members' names per process, and 256 read cursors a room.

It owns `/chat`, its own prefix.

Audited: 5395ae0 2026-10-27 docs/audit/M2.md
