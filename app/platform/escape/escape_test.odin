package escape

import "core:strings"
import "core:testing"

@(test)
esc_closes_every_way_out_of_text_and_attributes :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	esc(&b, `<script>alert('x')</script> & "q"`)
	testing.expect_value(t, strings.to_string(b), `&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; &#34;q&#34;`)
}

@(test)
json_esc_keeps_a_string_inside_its_quotes_and_its_script :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	json_esc(&b, "a \"q\" \\ </script> & tab\t\nline end")
	testing.expect_value(t, strings.to_string(b), `a \"q\" \\ \u003c/script\u003e \u0026 tab\t\nline\u2028end`)
}

@(test)
url_encode_escapes_the_query_specials :: proc(t: ^testing.T) {
	testing.expect_value(t, url_encode("a b&c=d/é"), "a%20b%26c%3Dd%2F%C3%A9")
}
