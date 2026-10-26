package stream

import "core:strings"

import http "fork:odin-http"

SSE_CONTENT_TYPE :: "text/event-stream"

// Answers with an SSE stream. The handler copies what it needs from the request first: after it
// returns, the request arena is scratch.
//
// The comment line goes out with the headers: WebKit (Playwright's build, S0.3) resolves a
// streamed fetch only at its first body bytes, so a quiet stream would stay "connecting" until the
// first heartbeat, and htmx's 60 s request timeout runs until the response resolves.
sse_begin :: proc(res: ^http.Response, user: rawptr = nil, on_close: http.Stream_Close_Proc = nil) -> ^http.Stream {
	stream_headers(res, SSE_CONTENT_TYPE)
	s := http.stream_begin(res, .Chunked, user, on_close = on_close)
	http.stream_write_string(s, SSE_OPEN)
	return s
}

SSE_OPEN :: ": open\n\n"

// One event block, in the temp allocator. hx-sse splits lines on CR, LF and CRLF (hx-sse.js:59-61),
// so every one of them in the payload starts a new `data:` line: splitting on LF alone would let a
// stray CR in user text start an `event:` or `id:` field. `id` and `event` come from the server
// and never hold a line break.
sse_event :: proc(id, event, data: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	if id != "" {
		strings.write_string(&b, "id: ")
		strings.write_string(&b, id)
		strings.write_byte(&b, '\n')
	}
	if event != "" {
		strings.write_string(&b, "event: ")
		strings.write_string(&b, event)
		strings.write_byte(&b, '\n')
	}
	start := 0
	for i := 0; i <= len(data); i += 1 {
		if i < len(data) && data[i] != '\r' && data[i] != '\n' { continue }
		strings.write_string(&b, "data: ")
		strings.write_string(&b, data[start:i])
		strings.write_byte(&b, '\n')
		if i + 1 < len(data) && data[i] == '\r' && data[i + 1] == '\n' { i += 1 }
		start = i + 1
	}
	strings.write_byte(&b, '\n')
	return strings.to_string(b)
}

// A comment line: hx-sse ignores it (hx-sse.js:75); it keeps proxies from timing an idle stream out
// and surfaces a dead peer as a send error.
SSE_HEARTBEAT :: ": hb\n\n"
