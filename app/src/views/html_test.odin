package views

import "core:strings"
import "core:testing"

// ---- tests for the escaping boundary: `odin test src/views` --------------
//
// Only what both the demo and the --minimal starter have (html.odin and
// page_head), so the file holds after `init --minimal` too.

@(test)
page_head_escapes_its_text :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	// What a fork passing a stored value to a heading would hand it.
	page_head(&b, `<b>`, `<script>alert(1)</script>`, `Tom & "Jerry"`)
	out := strings.to_string(b)
	testing.expect(t, !strings.contains(out, "<script>"), out)
	testing.expect(t, !strings.contains(out, "<b>"), out)
	testing.expect(t, strings.contains(out, `<h1>&lt;script&gt;alert(1)&lt;/script&gt;</h1>`), out)
	testing.expect(t, strings.contains(out, `Tom &amp; &#34;Jerry&#34;`), out)
}

@(test)
json_esc_keeps_a_string_inside_its_quotes_and_its_script :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	json_esc(&b, "a \"q\" \\ </script> & tab\t\nline\u2028end")
	testing.expect_value(t, strings.to_string(b), `a \"q\" \\ \u003c/script\u003e \u0026 tab\t\nline\u2028end`)
}
