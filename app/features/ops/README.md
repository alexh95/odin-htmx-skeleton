# ops

`/admin/ops` (PLAN §15.4, D36): what the process is doing, every second, for admins on the LAN (`Admin_Ops`,
`.Lan_Only`). Packages: `ops` (the domain: a minute of samples, the newest panel render and its tag, the crash file the
last run left, obs's modules and limits as rows for the views), `views` (the cards, server-side SVG sparklines, the
page) and `web` (the routes, the `ops.panel` topic, the `ops.sample` job).

**Rendered once.** The `ops.sample` job runs every second on the scheduler: it reads obs's registry (requests), the
streams (open, queued bytes), the hub (published, dropped, resyncs), the loops' ticks and the resident memory
(`sys.rss_bytes`: `/proc/self/statm` on Linux, the working set on Windows), renders the cards out of band
(`hx-swap-oob="innerMorph"`, so a card is morphed in place) and publishes them on `ops.panel` (`.Sample`: a viewer still
taking the last render skips this one). Every viewer gets that one copy, whichever refresh they chose (`?mode=`, D8):

| Mode | How |
|---|---|
| `sse` (default) | `ops.panel` on the page's `#live` |
| `poll` | `GET /admin/ops/panel` every second with hx-ptag: the kept render, or a 304 while it has it |
| `multipart` | `GET /admin/ops/parts`, a stream of its own on the topic, the kept render first |

The page also shows the declared limits and, after a restart, what the crash file (`CRASH_FILE`) says. On a nick build
an admin is a client in `ACCOUNTS_NICK_ADMIN_CIDRS` (none by default).

It owns `/admin/ops`, under its own `/admin/<f>` prefix.
