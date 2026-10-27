package escape

// ---- platform/escape: the injection boundary (L1) --------------------------
//
// Every dynamic value reaches a page through one of these: text through esc, a
// URL component through url_encode, a JSON string through json_esc; markup only
// through w. One definition of each: platform/html re-exports them (html.esc …)
// for views, and platform/markdown, which domains call at write time (L2), uses
// them directly. A leaf: core only.

import "core:fmt"
import "core:net"
import "core:strings"

w :: proc(b: ^strings.Builder, s: string) {
	strings.write_string(b, s)
}

// HTML-escapes text content. The only defence against an injected '<' from a
// search box or a contact name, so it is not optional anywhere input is echoed.
// Also correct inside a quoted attribute.
esc :: proc(b: ^strings.Builder, s: string) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&':  w(b, "&amp;")
		case '<':  w(b, "&lt;")
		case '>':  w(b, "&gt;")
		case '"':  w(b, "&#34;")
		case '\'': w(b, "&#39;")
		case:      strings.write_byte(b, s[i])
		}
	}
}

url_encode :: proc(s: string) -> string {
	return net.percent_encode(s, context.temp_allocator)
}

// A path on this site: never another origin (`//host`, `/\host`, which browsers
// read as `//host`), and no space or control byte. What a redirect's `next` and a
// link a producer hands the Inbox may be.
site_path :: proc(s: string) -> bool {
	if len(s) == 0 || s[0] != '/' || len(s) > 1 && (s[1] == '/' || s[1] == '\\') { return false }
	for c in transmute([]byte)s {
		if c < 0x21 || c == 0x7f { return false }
	}
	return true
}

// For the inside of a JSON string in a <script> block (JSON-LD). The HTML escaper
// is wrong there: entities aren't decoded inside <script>, so they would reach
// the JSON literally, and it leaves backslashes and control characters alone.
// `<`, `>` and `&` become \u escapes so the text can never close the script
// element; U+2028/9 too, which some JS parsers reject.
json_esc :: proc(b: ^strings.Builder, s: string) {
	for r in s {
		switch r {
		case '"':  w(b, `\"`)
		case '\\': w(b, `\\`)
		case '\n': w(b, `\n`)
		case '\r': w(b, `\r`)
		case '\t': w(b, `\t`)
		case '<', '>', '&', 0x00 ..< 0x20, 0x2028, 0x2029:
			fmt.sbprintf(b, `\u%04x`, int(r))
		case:
			strings.write_rune(b, r) // an invalid byte arrives as U+FFFD, re-encoded validly
		}
	}
}
