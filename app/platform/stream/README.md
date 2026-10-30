# platform/stream

The stream protocols on the fork's F-1, reached through `platform/web`'s re-export (PLAN §8.2, D12): the SSE encoder
(CR, LF and CRLF each start a `data:` line; `: open` goes out with the headers), the WebSocket handshake with its own
`Origin` check and a strict RFC 6455 codec (1002, 1007, 1009; 1013 to a slow consumer with a 2 s deadline, 1012 on
drain, 1011 after a pure crash), and the multipart writer (CRLF framing, a `Content-Length` per part). Every stream is
a `Conn` registered on its loop: one timer per loop sends SSE a comment line and a socket a ping every 20 s, and closes
a socket that has sent nothing for 45 s. A stream answers only from a `.Stream` row, whose headers `front` sends.
Layer L3 (PLAN §5.1).

Audited: 30988ae 2026-10-30 docs/audit/M4.md (`b64_decode` and its use, read in the re-read); c490e2a 2026-10-30 docs/audit/M3.md
