# odin-http: where this copy comes from

The starter's HTTP server is a fork of [laytan/odin-http](https://github.com/laytan/odin-http) (MIT, `LICENSE`),
vendored in-tree so that its changes live next to the code that needs them (D11; ANSWERS F3). There is no separate
fork repo: an upstream offer goes through a GitHub fork made at that time from the changes listed below (PLAN §8.1).

- **Base:** `fac113fbd828aad3d71479a534b5de4358b6a07b` (2026-08-26, "openssl: update bundled libraries to
  openssl-3.6.4 (#120)"), the commit the skeleton pinned as its `app/odin-http` submodule. Upstream had no newer
  commit when this was vendored (2026-10-26).
- **What is vendored:** only the `http` package's own files, `LICENSE` and `README.md`. Left out: `client/`,
  `comparisons/`, `docs/`, `examples/`, `old_nbio/`, `openssl/`, `.editorconfig` and `odinfmt.json`. The server path
  uses `core:nbio` and needs no OpenSSL.
- **Odin:** `dev-2026-10` (`84bc3fc`), the toolchain pin of the Dockerfile and CI.

## Local changes

Each change is generic (nothing starter-specific goes in here), keeps upstream's style, and is listed with the files
it touches. The WS codec, the SSE encoder, the multipart writer, Range parsing and the hub stay in the starter's
`platform/stream` and `platform/hub` (PLAN §8.1), so this diff stays small enough to offer upstream.

| # | Change | Files | Status |
|---|---|---|---|
| F-1 | Streams: a `Streaming` connection state, `Connection.stream`, and `stream.odin` (`stream_begin`, `stream_write`, `stream_end`, `stream_queued`, `stream_loop`, `on_data`, `on_close`, `on_shutdown`); chunked, raw (after a 101) and close-delimited bodies; a send queue capped at 256 KiB (`Too_Slow`) | `stream.odin`, `server.odin` | M0 spike (S0.2, S0.3) |
| F-2 | HTTP/1.0 peers get a close-delimited stream body instead of chunked | `stream.odin` | M0 spike |
| F-3 | `stream_sendfile` on `nbio.sendfile`, for Range responses | — | planned (M9's video) |
| F-4 | `Server_Opts.on_thread_init` and `on_thread_shutdown`, with each thread's index | `server.odin` | M0 spike (S0.6, S0.7) |
| F-5 | `Server_Opts.invoke`: accept, the scanner's reads (and the handler dispatch inside them), response sends and stream callbacks run through it; when it reports a crash, the connection answers 500 if nothing was sent and closes, and a stream gets `on_crash` and ends (`Stream_End.Crashed`) | `server.odin`, `scanner.odin`, `response.odin`, `stream.odin` | M0 spike (S0.2, S0.6) |
| F-6 | `Content-Length` must be plain digits within `int` (`parse_content_length`); anything else answers 400, so `-5` no longer reaches `assert(n >= 0)` in the scanner, `OPTIONS *` included | `body.odin` | M0 spike (S0.2, S0.6) |
| F-7 | Timeouts on the scanner's reads: idle 75 s, headers 10 s from a request's first byte, body 30 s (`idle_timeout`, `header_timeout`, `body_timeout`; 0 = none); a timed-out peer reads as EOF | `scanner.odin`, `server.odin` | M0 spike (S0.2, S0.7) |
| F-8 | `max_connections` (default: the open-file soft limit − 64 on Linux and macOS, none on Windows) answers 503 past the cap; an accept error is logged and the accept re-posted instead of `panicf` | `server.odin`, `limits_posix.odin`, `limits_windows.odin` | M0 spike (S0.2, S0.7) |
| F-9 | Bounded shutdown: the accept stops at once, idle connections and those still reading their headers close with their read cancelled, streams get 2 s, active requests `drain_deadline` (5 s) before their sockets are cut (past it, closing connections no longer hold the loop), and leftover operations 500 ms | `server.odin` | M0 spike (S0.7: 5.6 s with 500 SSE + 500 WS + a slowloris + a half body + an idle peer) |
| F-10 | SIGTERM as well as SIGINT; the second-signal check is a process-wide flag (upstream read a thread-local that is nil on a thread that isn't the server's); `server_is_closing` | `server.odin` | M0 spike (S0.7) |
| F-11 | The `date` header is formatted per thread, once per second of its loop's clock, instead of in one shared buffer a timer rewrote under the readers | `server.odin` | M0 spike (S0.2) |
| F-12 | `listen` logs an error naming io_uring and seccomp when the event loop can't start, instead of asserting, and retries a bind that fails with `Address_In_Use` for `bind_retry` (3 s) | `server.odin` | M0 spike (S0.7) |

"M0 spike" means the change is in and the named spikes exercise it (`docs/spikes/`); M1 productionises it with its own
tests (PLAN §22.3). Spike S0.2 measures F-1 and F-5..F-12 under the skeleton's k6 suite before anything builds on them.

## Bumping

1. Copy the new upstream commit's package files over this directory (same list as above), keeping this file.
2. Re-apply the local changes, one commit each, and update the table and the base line above.
3. Re-run the stream contract suite and the parity gate (PLAN §18) before anything ships on the new base.
