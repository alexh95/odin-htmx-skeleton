package stream_client

import "core:math/rand"
import "core:strings"
import "core:testing"

@(test)
heads_parse :: proc(t: ^testing.T) {
	text := "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nTransfer-Encoding: chunked\r\n\r\nrest"
	n := head_end(transmute([]byte)text)
	testing.expect_value(t, n, len(text) - 4)
	h, ok := parse_head(text[:n])
	testing.expect(t, ok && h.status == 200 && h.chunked && h.length == -1 && h.ctype == "text/event-stream")
	testing.expect_value(t, head_end(transmute([]byte)string("HTTP/1.1 200 OK\r\nX: y\r\n")), 0)

	h, ok = parse_head("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: abc=\r\n\r\n")
	testing.expect(t, ok && h.status == 101 && h.accept == "abc=")
	h, ok = parse_head("HTTP/1.1 204 No Content\r\ncontent-length: 0\r\n\r\n")
	testing.expect(t, ok && h.status == 204 && h.length == 0)
	_, ok = parse_head("SSH-2.0-OpenSSH\r\n\r\n")
	testing.expect(t, !ok)
}

// Every split of the body's bytes into two feeds decodes the same.
@(test)
chunked_decodes_across_any_split :: proc(t: ^testing.T) {
	body := "5\r\nhello\r\n1;ext=1\r\n \r\nC\r\n, streaming.\r\n0\r\nTrailer: x\r\n\r\nNEXT"
	want := "hello , streaming."
	for cut in 0 ..= len(body) {
		c: Chunked
		out: [dynamic]byte
		defer delete(out)
		b := transmute([]byte)body
		u1, d1, bad1 := chunked_feed(&c, b[:cut], &out)
		testing.expect(t, !bad1)
		done := d1
		used := u1
		if !done {
			u2, d2, bad2 := chunked_feed(&c, b[cut:], &out)
			testing.expect(t, !bad2)
			done, used = d2, cut + u2
		}
		testing.expectf(t, done && string(out[:]) == want && used == len(body) - 4, "cut %d: %q done %v used %d", cut, string(out[:]), done, used)
	}
}

@(test)
chunked_refuses_bad_framing :: proc(t: ^testing.T) {
	for bad in ([?]string{"x\r\n", "5\r\nhelloX\r\n", "\r\n", "1234567890abcdef0\r\n", "5\nhello"}) {
		c: Chunked
		out: [dynamic]byte
		_, _, is_bad := chunked_feed(&c, transmute([]byte)bad, &out)
		testing.expectf(t, is_bad, "%q accepted", bad)
		delete(out)
	}
}

@(private = "file")
Got :: struct {
	events: [dynamic]string,
}

@(test)
sse_reads_events_across_splits_and_line_ends :: proc(t: ^testing.T) {
	stream := ": open\r\n\r\nid: 1-2\r\ndata: a\rdata: b\n\nevent: resync\ndata: chat.room:1\r\n\r\n: hb\n\ndata:no space\r\r"
	want := [?]string{"1-2||a\nb", "1-2|resync|chat.room:1", "1-2||no space"}
	for cut in 0 ..= len(stream) {
		p: Sse
		got: Got
		on :: proc(user: rawptr, ev: Sse_Event) {
			g := (^Got)(user)
			append(&g.events, strings.concatenate({ev.id, "|", ev.event, "|", ev.data}, context.temp_allocator))
		}
		b := transmute([]byte)stream
		sse_feed(&p, b[:cut], &got, on)
		sse_feed(&p, b[cut:], &got, on)
		ok := len(got.events) == len(want)
		for e, i in got.events {
			if i < len(want) && e != want[i] { ok = false }
		}
		testing.expectf(t, ok, "cut %d: %v", cut, got.events[:])
		delete(got.events)
		sse_destroy(&p)
	}
}

@(test)
ws_frames_round_trip :: proc(t: ^testing.T) {
	testing.expect(t, ws_accept_ok("dGhlIHNhbXBsZSBub25jZQ==", "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="))
	for n in ([?]int{0, 5, 125, 126, 70_000}) {
		payload := make([]byte, n, context.temp_allocator)
		for &b in payload { b = byte(rand.uint32()) }
		out: [dynamic]byte
		ws_frame(&out, 0x2, payload)
		// What the server reads: masked; unmask it as the server would.
		testing.expect(t, out[1] & 0x80 != 0)
		header := 2 if n < 126 else 4 if n < 65536 else 10
		mask := out[header:][:4]
		ok := len(out) == header + 4 + n
		for i in 0 ..< n {
			if out[header + 4 + i] ~ mask[i & 3] != payload[i] { ok = false; break }
		}
		testing.expectf(t, ok, "%d bytes", n)
		delete(out)
	}
	// A server frame: unmasked; a close carries its code.
	f, n, bad := ws_read({0x88, 0x02, 0x03, 0xF4, 0xFF})
	testing.expect(t, !bad && n == 4 && f.op == 0x8 && f.code == 1012)
	_, n, bad = ws_read({0x81, 0x05, 'h', 'e'})
	testing.expect(t, !bad && n == 0)
	_, _, bad = ws_read({0x81, 0x85, 0, 0, 0, 0, 'h', 'e', 'l', 'l', 'o'})
	testing.expect(t, bad) // a server never masks
}
