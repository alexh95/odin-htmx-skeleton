package http

import "core:strings"
import "core:testing"

// F-14 and F-16's chunk framing, the parts that need no connection: the size and the line end.
// The decoder end to end is in the drills' malformed set (tools/drills).
@(test)
chunk_framing :: proc(t: ^testing.T) {
	Size :: struct {
		line: string,
		n:    int,
		ok:   bool,
	}
	sizes := []Size {
		{"5", 5, true},
		{"fF", 255, true},
		{"0", 0, true},
		{"0000000000000005", 5, true}, // leading zeros don't count toward 15 digits
		{"fffffffffffffff", 0xfffffffffffffff, true},
		{"1000000000000000", 0, false}, // 16 significant digits could wrap
		{"", 0, false},
		{"-5", 0, false},
		{"+5", 0, false},
		{"5_0", 0, false},
		{"5 ", 0, false}, // whitespace only before a ';', which the caller cuts at
		{" 5", 0, false},
		{"0x5", 0, false},
	}
	for c in sizes {
		n, ok := parse_chunk_size(c.line)
		testing.expectf(t, ok == c.ok && (!ok || n == c.n), "%q: %v %v", c.line, n, ok)
	}

	longest := strings.repeat("a", MAX_CHUNK_LINE, context.temp_allocator)
	Line :: struct {
		data:    string,
		advance: int,
		token:   string,
		bad:     bool,
	}
	lines := []Line {
		{"5\r\nhello", 3, "5", false},
		{"\r\n", 2, "", false},
		{"5;ext=1\r\n", 9, "5;ext=1", false},
		{"5", 0, "", false}, // not ended yet: wait for more
		{"5\r", 0, "", false},
		{"5\nhello", 0, "", true}, // a bare LF is bad framing
		{"\n", 0, "", true},
		{strings.concatenate({longest, "\r\n"}, context.temp_allocator), MAX_CHUNK_LINE + 2, longest, false},
		{strings.concatenate({longest, "a\r"}, context.temp_allocator), 0, "", true}, // past the bound, ended or not
	}
	for c in lines {
		advance, token, err, _ := scan_crlf_lines(nil, transmute([]byte)c.data, false)
		testing.expectf(t, advance == c.advance && string(token) == c.token && (err != nil) == c.bad,
			"%q: advance %d token %q err %v", c.data[:min(len(c.data), 16)], advance, string(token), err)
	}
	// An empty line is a token, not "no token yet": the scanner tells them apart by nil.
	_, empty, _, _ := scan_crlf_lines(nil, transmute([]byte)string("\r\n"), false)
	testing.expect(t, empty != nil)

	// Trailer lines take a bare LF (they are field lines) but not past the bound.
	_, tok, err, _ := scan_trailer_lines(nil, transmute([]byte)string("X-T: 1\nrest"), false)
	testing.expectf(t, string(tok) == "X-T: 1" && err == nil, "%q %v", string(tok), err)
	_, _, err, _ = scan_trailer_lines(nil, transmute([]byte)strings.concatenate({longest, "aa"}, context.temp_allocator), false)
	testing.expect(t, err != nil)
	free_all(context.temp_allocator)
}

// M2-21: a POST stream's handler runs from its body's callback and begins its stream there, after
// the headers' end looked; once that callback returns, the connection's arena goes back, as it
// does for a handler called from the headers (F-17). A request that didn't begin a stream keeps it.
@(test)
post_stream_gives_its_arena_back :: proc(t: ^testing.T) {
	Probe :: struct {
		c:     ^Connection,
		s:     Stream,
		begin: bool,
	}
	handler :: proc(user: rawptr, _: Body, _: Body_Error) {
		p := (^Probe)(user)
		_ = make([]byte, 4096, conn_arena_allocator(&p.c.temp_allocator))
		if p.begin { p.c.stream = &p.s } // as stream_begin sets it
	}
	for begin in ([]bool{true, false}) {
		c := new(Connection)
		conn_arena_init(&c.temp_allocator)
		c.loop.conn = c
		p := Probe{c = c, begin = begin}
		c.loop.req._body_cb, c.loop.req._body_user = handler, &p
		_body_returned(&c.loop.req, "", nil)
		testing.expectf(t, (c.temp_allocator.curr_block == nil) == begin, "stream begun %v: arena block %p", begin, c.temp_allocator.curr_block)
		c.stream = nil
		conn_arena_destroy(&c.temp_allocator)
		free(c)
	}
}
