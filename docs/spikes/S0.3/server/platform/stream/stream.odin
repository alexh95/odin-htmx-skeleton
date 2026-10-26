// platform/stream, as spike S0.3 shapes it: the protocol code on top of the fork's streams (F-1),
// with nothing of the hub or the app in it (PLAN §8.2; D12). Three pieces:
//
// - sse.odin:       the SSE encoder (CR, LF and CRLF each end a `data:` line);
// - ws.odin:        the WebSocket handshake with its own Origin check, and a strict RFC 6455 codec;
// - multipart.odin: the multipart/mixed writer (CRLF framing, a Content-Length per part, one chunk each).
//
// The Range sender is M9's and is not here. In the plan only platform/web imports odin-http; this
// spike imports the fork directly.
package stream

import http "fork:odin-http"

// Every stream response says so, so that nginx (NPM) flushes each write instead of buffering the
// body, and no cache holds a live stream (PLAN §8.2; 08 §3.2).
stream_headers :: proc(res: ^http.Response, content_type: string) {
	http.headers_set_unsafe(&res.headers, "content-type", content_type)
	http.headers_set_unsafe(&res.headers, "cache-control", "no-cache")
	http.headers_set_unsafe(&res.headers, "x-accel-buffering", "no")
}
