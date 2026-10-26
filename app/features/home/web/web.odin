package home_web

// ---- home: the root page of `minimal` (and of Houston's main host, M4) ----------------------
//
// The profile's HOME_CARDS in the table's order, under the profile's heading. Its
// one row is the root, which the profile writes in its routes.odin, so the same
// page can sit at / in one profile and elsewhere in another (§6.3).

import "core:strings"

import "../../../platform/html"
import "../../../platform/web"

EXTS :: web.Exts{}

// The profile's words for its home page (brand.odin).
Copy :: struct {
	title, eyebrow, heading, lede, description: string,
}

@(private)
st: struct {
	cards: []html.Home_Card,
	copy:  Copy,
}

init :: proc(cards: []html.Home_Card, copy: Copy) {
	st.cards, st.copy = cards, copy
}

page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, st.copy.eyebrow, st.copy.heading, st.copy.lede)
	v := web.viewer(req)
	for card in st.cards {
		card(&b, v)
	}
	web.render_page(req, res, st.copy.title, "/", st.copy.description, strings.to_string(b))
}
