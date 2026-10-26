# lab

The stream contract pages (PLAN §15.5): `/lab/streams` and its pages use hx-sse, hx-ws and hx-multipart against
`platform/stream` and `platform/hub` the way a real page does (one layout SSE stream, one socket inside the swapped
region, parts into their own targets), and the endpoints beside them are what 03's 29 contract checks and the
extension specs in `e2e/tests/lab/` drive: a ticking SSE answer, the WebSocket echo the nightly Autobahn run fuzzes,
a room, multipart parts and a resumable multipart feed, publish and close for a `lab.feed` or `lab.room` topic, and
`/lab/stats`. Topics `lab.bus` (a producer job's beats), `lab.feed:<key>` and `lab.room:<key>`. The lab is a public
origin with no sessions, so nothing takes markup from a request: published text is escaped into a fixed fragment and
every key is 1-40 of `[a-z0-9-]`. Packages: `views`, `web`; no store. It owns `/lab`, its own prefix.

Audited: none yet (new in M2; `docs/audit/M2.md`)
