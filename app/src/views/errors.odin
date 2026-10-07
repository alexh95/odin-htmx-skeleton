package views

import "core:strings"

// ---- error pages --------------------------------------------------------
//
// The body of the page a person sees when a full-page request fails (a 404, a
// store error); the controllers wrap it in layout(). Shared by the demo and the
// `init --minimal` starter. `title` and `message` are text, escaped here.
view_error :: proc(title, message: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<header class="page-head"><p class="eyebrow">Error</p><h1>`)
	esc(&b, title)
	w(&b, `</h1><p class="lede">`)
	esc(&b, message)
	w(&b, `</p></header><p><a class="btn btn-primary" href="/">Back to the home page</a></p>`)
	return strings.to_string(b)
}
