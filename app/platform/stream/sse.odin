package stream

import "core:strings"

import "../web"

SSE_CONTENT_TYPE :: "text/event-stream"

// The first bytes, sent with the headers: WebKit resolves a streamed fetch only
// at its first body bytes, so a quiet stream stayed "connecting" until the first
// heartbeat (19.6 s), inside htmx's 60 s request timeout (S0.3).
SSE_OPEN :: ": open\n\n"

// A comment line: hx-sse skips it; it keeps a proxy from timing an idle stream
// out and surfaces a dead peer as a send error.
SSE_HEARTBEAT :: ": hb\n\n"

// Answers with an SSE stream, or nil when admission refused it (the 503 or 429
// has been sent). Copy what the stream needs from the request first: once the
// handler returns, the request arena is scratch.
sse_begin :: proc(res: ^web.Response, user: rawptr = nil, on_close: Close_Proc = nil) -> ^Conn {
	c := open(res, .Chunked, .Sse, SSE_CONTENT_TYPE, user, on_close)
	if c != nil { write(c, SSE_OPEN) }
	return c
}

sse_send :: proc(c: ^Conn, id, event, data: string) -> bool {
	return write(c, sse_event(id, event, data))
}

// One event block. hx-sse splits lines on CR, LF and CRLF alike, so each of
// them in the payload starts a new `data:` line: splitting on LF alone would let
// a stray CR in user text start an `event:` or `id:` field. `id` and `event` are
// the server's and never hold a line break.
sse_event :: proc(id, event, data: string, allocator := context.temp_allocator) -> string {
	assert(strings.index_any(id, "\r\n") < 0 && strings.index_any(event, "\r\n") < 0)
	b := strings.builder_make(0, len(data) + len(id) + len(event) + 32, allocator)
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
