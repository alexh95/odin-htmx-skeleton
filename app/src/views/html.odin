package views

import "core:fmt"
import "core:net"
import "core:strings"

// ---- html: the escaping boundary ----------------------------------------
//
// Every dynamic value reaches the page through one of these: text through esc,
// a URL component through url_encode, a JSON string through json_esc. Shared by
// the demo and the `init --minimal` starter, so there is one definition of each.
//
// The helpers that build markup (page_head, section_open, stat_card, …) escape
// their text arguments themselves, so passing them a value from the database is
// safe; markup only ever goes in through w().

w :: proc(b: ^strings.Builder, s: string) {
	strings.write_string(b, s)
}

// HTML-escape text content. The only defence against an injected '<' from a
// search box or a contact name, so it is not optional anywhere user input is
// echoed. Also correct inside a quoted attribute.
esc :: proc(b: ^strings.Builder, s: string) {
	for i in 0 ..< len(s) {
		switch s[i] {
		case '&': w(b, "&amp;")
		case '<': w(b, "&lt;")
		case '>': w(b, "&gt;")
		case '"': w(b, "&#34;")
		case '\'': w(b, "&#39;")
		case: strings.write_byte(b, s[i])
		}
	}
}

// Restores the saved theme before first paint, so the page never flashes the
// default palette. It has to be inline (it must run before the stylesheet
// applies), so the Content-Security-Policy admits it by its hash, computed from
// this constant at boot (controllers.init_security): edit it here and the
// header follows. Every other script is a file.
THEME_PREPAINT_JS :: `try{var d=document.documentElement,s=localStorage.getItem('style'),c=localStorage.getItem('scheme');if(s)d.dataset.style=s;if(c)d.dataset.scheme=c;}catch(e){}`

url_encode :: proc(s: string) -> string {
	return net.percent_encode(s, context.temp_allocator)
}

// Escape s for the inside of a JSON string in a <script> block (JSON-LD). The
// HTML escaper is wrong here: entities are not decoded inside <script>, so they
// would reach the JSON literally, and it leaves backslashes and control
// characters alone. `<`, `>` and `&` become \u escapes so the text can never
// close the script element; U+2028/9 too, which some JS parsers reject.
json_esc :: proc(b: ^strings.Builder, s: string) {
	for r in s {
		switch r {
		case '"': w(b, `\"`)
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
