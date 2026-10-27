# M2 stream budgets

**Budgets:** PLAN §18.4's fan-out, restart and per-stream RSS rows, on the Linux leg with 4 event loops (§9.5: Windows
puts connections on one loop or spreads them unevenly, so fan-out claims are the Linux leg's) · **Result:** every row
met, the per-stream RSS row once the fork's F-17 was in (16.2 KiB an idle stream before it) · **Date:** 2026-10-27 ·
**Candidate:** the `lab` profile at M2's slice 6 (local commits after `b459ed8`), `-o:speed` · **Tool:**
`tools/streamload` on `platform/stream/client`, against the lab's endpoints (`/events?t=lab.feed:<key>`,
`/lab/ws/chat?room=<key>`, `/lab/publish`)

## Results

| Budget (§18.4) | Run | Measured | Verdict |
|---|---|---|---|
| 1000 SSE subscribers, p99 ≤ 100 ms | `fanout --sse 1000 --publish 50 --every 20` | 50,000 of 50,000 delivered; p50 2.0, p95 3.9, p99 21.8 ms | met |
| 3000 SSE subscribers, p99 ≤ 200 ms | `fanout --sse 3000 --publish 50 --every 20`, 5 runs | p99 9.7–10.6 ms; 150,000 of 150,000 in 4 runs, 149,950 in one (below) | met |
| WS 1000 sockets × 20 messages delivered ≤ 2 s | `fanout --ws 1000 --publish 20 --every 0` | 20,000 of 20,000; p99 21.6 ms from publish to delivery | met |
| 4000 clients back ≤ 3 s after a restart | `restart --sse 2000 --ws 2000 --publish 3`; `kill -9`, a new process 0.2 s later | 4000 of 4000 back 1.69 s after the first drop | met |
| stale cursors → replay or resync, 100 % | the same run: each SSE client resumes with its old epoch's `Last-Event-ID` | 2000 of 2000 resynced | met |
| ≤ 6 KiB per open stream; 8,192 idle ≤ +80 MB | `hold --sse 4000`, then `hold --ws 4000`; the server's `VmRSS` idle and holding | SSE 3,000 B, WS 5,008 B a stream (8,192: about 24 and 41 MB) | met with F-17 |

- **Per-stream RSS before F-17:** 16.2 KiB an idle stream, SSE or WS alike (4000 held: 68 MB over 5 MB idle). An idle
  stream held F-1's inline 4 KiB receive buffer, the scanner's heap buffer and the pages its request had touched in
  the connection's arena. F-17 sizes the receive buffer by kind (64 B for a chunked stream, which reads only to
  notice the peer leaving; 2 KiB for a socket), returns the scanner's buffer at `stream_begin`, and once the handler
  returns gives the arena back, zeroed so that its first block is mapped only on use (re-initialising it touched a
  page: 7.1 and 9.1 KiB a stream with that, 3.0 and 5.0 KiB without).
- **The 149,950:** once in five runs one subscriber got none of the 50 messages, before streamload counted messages
  per client; four runs since delivered every message to every client. Its report now names any client that came up
  short.
- **Server RSS at the end of a run:** 8.9 MB (1000 SSE) and 16.5 MB (3000 SSE), F-17 in.
- **Windows** (16 loops, the same binary, no budget): 200 SSE + 200 WS × 20 messages, all delivered, p99 2.5 ms.

## Method

- **Box:** the dev PC, Ubuntu on WSL2 (kernel 6.18), the server and streamload in WSL's own filesystem (`~/m2`, a copy
  of the working tree). Other sessions' Docker stacks were running in WSL (`top`'s wait column read 86–92 %, its idle
  6–13 %), so these are upper bounds on latency.
- **Server:** `THREADS=4 LOG_LEVEL=warn STREAM_CONNECTS=1000000 STREAMS_PER_CLIENT=100000 LAB_PUBLISH_PER_MINUTE=100000000 ./app/bin/lab` (one client
  opens thousands of streams; the totals keep their defaults), `ulimit -n 65536`.
- **Client:** `odin build tools/streamload -o:speed`; 4 threads, each an event loop holding its share of the clients.
  The publisher stamps each message with its own monotonic clock (`t=<ns>`), which every client reads back, so a
  latency is publish to delivery inside one process.
- **Restart:** streamload holds 2000 SSE and 2000 WS clients, publishes 3 messages so each SSE client has a cursor,
  then the server is killed with `kill -9` and a new one started 0.2 s later on the same port; each client reconnects
  after 0.5 s ±30 % (htmx's first backoff), SSE with its `Last-Event-ID`.
- **Scripts:** the run's shell scripts are in the session's scratch; the commands are the table's.
