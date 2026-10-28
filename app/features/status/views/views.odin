package status_views

// ---- status: the views (PLAN §15.4) ----------------------------------------------------------
//
// A card per probe, `#st-<name>`: the page writes them as "checking", and the board fills each
// as its probe answers (a part of a multipart/parallel response), or all at once out of band
// on a poll. What a probe says beyond its state is for admins (§15.4: details sit behind
// Admin_Ops).

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import status ".."

w :: html.w
esc :: html.esc

page :: proc(probes: []status.Probe, wiring: string, poll: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Operate", "Status", "Is everything up?")
	fmt.sbprintf(&b, `<section class="block"><div id="status-board" class="status-board"%s>`, wiring)
	for p in probes {
		fmt.sbprintf(&b, `<article id="st-%s" class="card status-card status-checking"><h2>`, p.name)
		esc(&b, p.name)
		w(&b, `</h2><p class="status-state">checking…</p></article>`)
	}
	w(&b, `</div><p class="muted">`)
	if poll {
		w(&b, `Checked every 30 seconds. <a href="/status">Once, in parallel</a>`)
	} else {
		w(&b, `Each line arrives as its check answers. <a href="/status?mode=poll">Every 30 seconds</a>`)
	}
	w(&b, `</p></section>`)
	return strings.to_string(b)
}

// One probe's card; `oob` for a poll's answer.
card :: proc(b: ^strings.Builder, p: status.Probe, details, oob: bool) {
	fmt.sbprintf(b, `<article id="st-%s" class="card status-card status-%s"%s><h2>`, p.name, p.state, ` hx-swap-oob="outerHTML"` if oob else "")
	esc(b, p.name)
	w(b, `</h2><p class="status-state">`)
	esc(b, p.state)
	w(b, `</p>`)
	if (details || p.public) && p.message != "" {
		w(b, `<p class="muted">`)
		esc(b, p.message)
		w(b, `</p>`)
	}
	w(b, `</article>`)
}
