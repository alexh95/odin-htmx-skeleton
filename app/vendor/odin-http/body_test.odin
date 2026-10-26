package http

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
	}
	for c in lines {
		advance, token, err, _ := scan_crlf_lines(nil, transmute([]byte)c.data, false)
		testing.expectf(t, advance == c.advance && string(token) == c.token && (err != nil) == c.bad,
			"%q: advance %d token %q err %v", c.data, advance, string(token), err)
	}
}
