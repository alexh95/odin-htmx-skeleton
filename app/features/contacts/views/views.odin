package contacts_views

// ---- contacts: the views ----------------------------------------------------------------------
//
// The skeleton's table, drawer and search dropdown (SK/app/src/views/), as the
// contacts feature's own package: HTML builders over a strings.Builder, every
// value through esc, url_encode or json_esc.

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import contacts ".."
import m "../models"

w :: html.w
esc :: html.esc
page_head :: html.page_head

// The whole swappable table: header controls, sortable columns, rows, and the
// pager. Sort and page links carry the current query so state is encoded in
// the request, not stashed on the client.
region :: proc(p: contacts.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div id="contact-region" class="card table-card"><div class="table-meta"><div class="table-filters">`)
	filter_chip(&b, p, "all", "All")
	for name in m.STATUS_NAMES {
		filter_chip(&b, p, name, name)
	}
	fmt.sbprintf(
		&b,
		`</div><span class="muted">%d %s</span></div>`,
		p.total,
		p.total == 1 ? "contact" : "contacts",
	)

	w(&b, `<div class="table-scroll"><table class="table"><thead><tr>`)
	sort_th(&b, p, "name", "Name")
	sort_th(&b, p, "email", "Email")
	sort_th(&b, p, "role", "Role")
	sort_th(&b, p, "status", "Status")
	sort_th(&b, p, "score", "Engagement")
	w(&b, `<th class="th-actions">Actions</th></tr></thead><tbody id="contact-tbody">`)

	if len(p.rows) == 0 {
		w(&b, `<tr class="row-empty"><td colspan="6"><div class="empty">`)
		html.icon(&b, "search")
		w(&b, `<p>No contacts match that filter.</p></div></td></tr>`)
	} else {
		for c in p.rows {
			row(&b, c, false)
		}
	}
	w(&b, `</tbody></table></div>`)

	pager(&b, p)
	w(&b, `</div>`)
	return strings.to_string(b)
}

// One column header. Shows the active direction and links to the next state
// (asc -> desc -> asc) via contacts.next_sort.
// A status quick-filter chip. "all" clears the filter; the active chip is marked.
@(private = "file")
filter_chip :: proc(b: ^strings.Builder, p: contacts.Page, value, label: string) {
	active := value == "all" ? (p.status == "" || p.status == "all") : (p.status == value)
	q := value == "all" ? "" : value
	fmt.sbprintf(
		b,
		`<button class="chip-filter%s" hx-get="/contacts?q=%s&status=%s&sort=%s&page=1" hx-target="#contact-region" hx-swap="outerHTML">%s</button>`,
		active ? " is-active" : "",
		html.url_encode(p.q),
		html.url_encode(q),
		html.url_encode(p.sort),
		label,
	)
}

@(private = "file")
sort_th :: proc(b: ^strings.Builder, p: contacts.Page, column, label: string) {
	dir := "none"
	if p.sort == column {
		dir = "asc"
	} else if p.sort == strings.concatenate({column, "_desc"}, context.temp_allocator) {
		dir = "desc"
	}
	fmt.sbprintf(
		b,
		`<th><button class="sort" data-dir="%s" hx-get="/contacts?q=%s&status=%s&sort=%s&page=1" hx-target="#contact-region" hx-swap="outerHTML">%s<span class="caret"></span></button></th>`,
		dir,
		html.url_encode(p.q),
		html.url_encode(p.status),
		contacts.next_sort(p.sort, column),
		label,
	)
}

// Prev, the first and last pages, the current one with PAGER_WINDOW either
// side, and a gap (…) for what's skipped. A button for every page was 2,864 of
// them at 20k rows: 400 KB of pager for one table.
PAGER_WINDOW :: 2

@(private = "file")
pager :: proc(b: ^strings.Builder, p: contacts.Page) {
	if p.total_pages <= 1 {
		return
	}
	w(b, `<nav class="pager" aria-label="Pagination">`)
	page_btn(b, p, p.page - 1, "‹ Prev", p.page <= 1)
	shown := 0
	for n in 1 ..= p.total_pages {
		if n != 1 && n != p.total_pages && abs(n - p.page) > PAGER_WINDOW {
			continue
		}
		if n > shown + 1 {
			w(b, `<span class="page-gap" aria-hidden="true">…</span>`)
		}
		shown = n
		if n == p.page {
			fmt.sbprintf(b, `<button class="page is-current" aria-current="page">%d</button>`, n)
			continue
		}
		fmt.sbprintf(
			b,
			`<button class="page" hx-get="/contacts?q=%s&status=%s&sort=%s&page=%d" hx-target="#contact-region" hx-swap="outerHTML">%d</button>`,
			html.url_encode(p.q),
			html.url_encode(p.status),
			html.url_encode(p.sort),
			n,
			n,
		)
	}
	page_btn(b, p, p.page + 1, "Next ›", p.page >= p.total_pages)
	w(b, `</nav>`)
}

@(private = "file")
page_btn :: proc(b: ^strings.Builder, p: contacts.Page, target: int, label: string, disabled: bool) {
	if disabled {
		fmt.sbprintf(b, `<button class="page" disabled>%s</button>`, label)
		return
	}
	fmt.sbprintf(
		b,
		`<button class="page" hx-get="/contacts?q=%s&status=%s&sort=%s&page=%d" hx-target="#contact-region" hx-swap="outerHTML">%s</button>`,
		html.url_encode(p.q),
		html.url_encode(p.status),
		html.url_encode(p.sort),
		target,
		label,
	)
}

// A single contact row. `fresh` adds the entrance highlight used when a row is
// appended after a create. To refresh the row behind the detail drawer the
// controller wraps this in an <hx-partial> targeting #contact-<id> (see
// contacts_update) — no per-row OOB attribute needed.
row :: proc(b: ^strings.Builder, c: m.Contact, fresh: bool) {
	fmt.sbprintf(
		b,
		`<tr id="contact-%d" class="%s">`,
		c.id,
		fresh ? "row row-new" : "row",
	)

	fmt.sbprintf(
		b,
		`<td class="c-name"><button class="c-open" type="button" hx-get="/contacts/%d" hx-target="#overlay" hx-swap="innerHTML" title="View contact">`,
		c.id,
	)
	html.avatar(b, c.id, c.name)
	w(b, `<span class="c-name-text"><strong>`)
	esc(b, c.name)
	fmt.sbprintf(b, `</strong><small>#%d</small></span></button></td>`, c.id)

	w(b, `<td class="c-email">`)
	esc(b, c.email)
	w(b, `</td><td>`)
	role_chip(b, c.role)
	w(b, `</td><td>`)
	status_badge(b, c.status)
	fmt.sbprintf(
		b,
		`</td><td class="c-score"><div class="meter"><i style="width:%d%%"></i></div><small>%d</small></td>`,
		c.score,
		c.score,
	)

	// hx-vals is literal JSON; its braces can't go through fmt (see layout).
	fmt.sbprintf(
		b,
		`<td class="c-actions"><button class="icon-btn" title="Cycle status" hx-post="/contacts/%d" hx-vals='`,
		c.id,
	)
	w(b, `{"action":"cycle"}`)
	fmt.sbprintf(b, `' hx-target="#contact-%d" hx-swap="outerHTML">`, c.id)
	html.icon(b, "cycle")
	fmt.sbprintf(
		b,
		`</button><button class="icon-btn danger" title="Delete" hx-delete="/contacts/%d" hx-target="#contact-%d" hx-swap="outerHTML swap:220ms" hx-confirm="Delete this contact?">`,
		c.id,
		c.id,
	)
	html.icon(b, "trash")
	w(b, `</button></td></tr>`)
}

// The contact detail drawer — the drilldown past the table row. `detail`
// returns the backdrop + aside (loaded into #overlay on open); the `detail_frag` variant
// returns just the aside, for in-place swaps (edit toggle / save / cycle) that target
// `.drawer-detail` so the backdrop doesn't re-animate.
detail :: proc(c: m.Contact, timeline: []m.Interaction, related: []m.Contact) -> string {
	b := strings.builder_make(context.temp_allocator)
	// from:self: only a click on the backdrop itself closes it, not one that
	// bubbles up from inside the drawer.
	w(&b, `<div class="backdrop" hx-get="/ui/clear" hx-trigger="click from:self" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	detail_aside(&b, c, timeline, related, false, false)
	w(&b, `</div>`)
	return strings.to_string(b)
}

detail_frag :: proc(c: m.Contact, timeline: []m.Interaction, related: []m.Contact, editing: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	detail_aside(&b, c, timeline, related, editing, true)
	return strings.to_string(b)
}

// A drawer edit that failed validation (422): the header still shows the
// stored contact, the form what the user typed, with the reason.
edit_rejected :: proc(stored, typed: m.Contact, msg: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	detail_head(&b, stored, true)
	detail_edit_form(&b, typed, msg)
	w(&b, `</aside>`)
	return strings.to_string(b)
}

@(private = "file")
detail_aside :: proc(b: ^strings.Builder, c: m.Contact, timeline: []m.Interaction, related: []m.Contact, editing, static_anim: bool) {
	detail_head(b, c, static_anim)
	if editing {
		detail_edit_form(b, c, "")
	} else {
		detail_view_body(b, c, timeline, related)
	}
	w(b, `</aside>`)
}

// Opens the <aside>; the caller closes it.
@(private = "file")
detail_head :: proc(b: ^strings.Builder, c: m.Contact, static_anim: bool) {
	// drawer-static skips the slide-in so in-place swaps don't re-animate.
	fmt.sbprintf(
		b,
		`<aside class="drawer drawer-detail%s" role="dialog" aria-modal="true" aria-label="Contact detail"><header class="drawer-head detail-head">`,
		static_anim ? " drawer-static" : "",
	)
	html.avatar(b, c.id, c.name)
	w(b, `<div class="detail-id"><h2>`)
	esc(b, c.name)
	w(b, `</h2><p class="muted">`)
	esc(b, c.email)
	w(b, `</p></div><button class="icon-btn detail-close" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	html.icon(b, "plus")
	w(b, `</button></header>`)
}

@(private = "file")
detail_view_body :: proc(b: ^strings.Builder, c: m.Contact, timeline: []m.Interaction, related: []m.Contact) {
	rn := m.ROLE_NAMES
	w(b, `<div class="detail-body"><div class="detail-actions">`)
	fmt.sbprintf(b, `<button class="btn btn-outline btn-sm" hx-get="/contacts/%d?edit=1&frag=1" hx-target="closest .drawer-detail" hx-swap="outerHTML">`, c.id)
	html.icon(b, "edit")
	w(b, `<span>Edit</span></button>`)
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm" hx-post="/contacts/%d" hx-vals='`, c.id)
	w(b, `{"action":"cycle","view":"detail","frag":"1"}`)
	w(b, `' hx-target="closest .drawer-detail" hx-swap="outerHTML">`)
	html.icon(b, "cycle")
	w(b, `<span>Cycle</span></button>`)
	// swapEmpty:true is load-bearing: the delete-from-drawer response is an empty body
	// plus one OOB <tr> (see contacts_delete), and closing the drawer *is* that empty
	// swap. htmx 4.0.0 made an OOB swap suppress an empty main swap by default, which
	// left the drawer open; this opts that suppression back out for this one button.
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm danger" hx-delete="/contacts/%d?from=drawer" hx-target="#overlay" hx-swap="innerHTML swap:240ms swapEmpty:true" hx-confirm="Delete this contact?">`, c.id)
	html.icon(b, "trash")
	w(b, `<span>Delete</span></button></div><div class="detail-meta">`)
	role_chip(b, c.role)
	status_badge(b, c.status)
	fmt.sbprintf(b, `<span class="detail-score"><small class="muted">Engagement</small><div class="meter"><i style="width:%d%%"></i></div><strong>%d / 100</strong></span><span class="detail-rid">#%d</span>`, c.score, c.score, c.id)
	if c.notify {
		w(b, `<span class="tag">email updates</span>`)
	}
	w(b, `</div>`)
	if c.notes != "" {
		w(b, `<section class="detail-section"><h3>Notes</h3><p class="detail-notes">`)
		esc(b, c.notes)
		w(b, `</p></section>`)
	}
	w(b, `<section class="detail-section"><h3>Activity</h3>`)
	if len(timeline) == 0 {
		w(b, `<p class="muted detail-empty">No interactions yet.</p>`)
	} else {
		w(b, `<ol class="timeline">`)
		for it in timeline {
			w(b, `<li><span class="tl-dot">`)
			html.icon(b, interaction_icon(it.kind))
			w(b, `</span><div class="tl-body"><strong>`)
			interaction_label(b, it)
			w(b, `</strong><small>`)
			if it.note != "" {
				esc(b, it.note)
				w(b, ` · `)
			}
			esc(b, contacts.time_ago(it.at))
			w(b, `</small></div></li>`)
		}
		w(b, `</ol>`)
	}
	w(b, `</section>`)
	if len(related) > 0 {
		fmt.sbprintf(b, `<section class="detail-section"><h3>Also in %s</h3><div class="related-list">`, rn[c.role])
		for r in related {
			fmt.sbprintf(b, `<button class="related-item" type="button" hx-get="/contacts/%d" hx-target="#overlay" hx-swap="innerHTML">`, r.id)
			html.avatar(b, r.id, r.name)
			w(b, `<span class="related-name"><strong>`)
			esc(b, r.name)
			w(b, `</strong><small>`)
			esc(b, r.email)
			w(b, `</small></span></button>`)
		}
		w(b, `</div></section>`)
	}
	w(b, `</div>`)
}

// One timeline entry's headline, with the other contact as a one-click jump:
// "Reviewed <Grace Hopper>" (outgoing) or "<Grace Hopper> reviewed you" (incoming).
@(private = "file")
interaction_label :: proc(b: ^strings.Builder, it: m.Interaction) {
	names := m.EVENT_KIND_NAMES
	verb := names[it.kind]
	if it.outgoing {
		esc(b, verb)
		w(b, ` `)
		who_link(b, it.other_id, it.other_name)
	} else {
		who_link(b, it.other_id, it.other_name)
		w(b, ` `)
		esc(b, strings.to_lower(verb, context.temp_allocator))
		w(b, ` you`)
	}
}

@(private = "file")
who_link :: proc(b: ^strings.Builder, id: i64, name: string) {
	fmt.sbprintf(b, `<button class="tl-who" type="button" hx-get="/contacts/%d" hx-target="#overlay" hx-swap="innerHTML">`, id)
	esc(b, name)
	w(b, `</button>`)
}

@(private = "file")
interaction_icon :: proc(kind: m.Event_Kind) -> string {
	switch kind {
	case .Introduced:
		return "users"
	case .Mentioned:
		return "bell"
	case .Reviewed:
		return "check"
	case .Messaged:
		return "bolt"
	}
	return "bolt"
}

// `problem` (if any) is shown above the buttons: why the last save was refused.
@(private = "file")
detail_edit_form :: proc(b: ^strings.Builder, c: m.Contact, problem: string) {
	rn := m.ROLE_NAMES
	sn := m.STATUS_NAMES
	fmt.sbprintf(b, `<form class="detail-body detail-edit" hx-post="/contacts/%d" hx-target="closest .drawer-detail" hx-swap="outerHTML"><input type="hidden" name="view" value="detail"><input type="hidden" name="frag" value="1"><label class="field"><span>Name</span><input name="name" required maxlength="%d" value="`, c.id, contacts.MAX_NAME)
	esc(b, c.name)
	fmt.sbprintf(b, `"></label><label class="field"><span>Email</span><input name="email" type="email" required maxlength="%d" value="`, contacts.MAX_EMAIL)
	esc(b, c.email)
	w(b, `"></label><label class="field"><span>Role</span><select name="role">`)
	for name, r in rn {
		fmt.sbprintf(b, `<option%s>%s</option>`, r == c.role ? " selected" : "", name)
	}
	w(b, `</select></label><label class="field"><span>Status</span><select name="status">`)
	for name, st in sn {
		fmt.sbprintf(b, `<option%s>%s</option>`, st == c.status ? " selected" : "", name)
	}
	w(b, `</select></label>`)
	fmt.sbprintf(b, `<label class="field"><span>Engagement <output>%d</output></span><input name="score" type="range" min="0" max="100" value="%d"%s></label>`, c.score, c.score, html.behave_attr(.Range_Fill))
	if problem != "" {
		w(b, `<p class="field-msg form-error" role="alert">`)
		w(b, html.field_msg(false, problem))
		w(b, `</p>`)
	}
	w(b, `<div class="detail-actions"><button class="btn btn-primary btn-sm" type="submit">`)
	html.icon(b, "check")
	w(b, `<span>Save</span></button>`)
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm" type="button" hx-get="/contacts/%d?frag=1" hx-target="closest .drawer-detail" hx-swap="outerHTML">Cancel</button></div></form>`, c.id)
}

// ---- search dropdown ----------------------------------------------------

search_results :: proc(q: string, rows: []m.Contact) -> string {
	b := strings.builder_make(context.temp_allocator)
	trimmed := strings.trim_space(q)
	if trimmed == "" {
		return "" // empty target collapses the dropdown
	}

	if len(rows) == 0 {
		w(&b, `<div class="search-panel"><p class="search-empty">No matches for “`)
		esc(&b, trimmed)
		w(&b, `”.</p></div>`)
		return strings.to_string(b)
	}

	w(&b, `<div class="search-panel"><ul class="search-list">`)
	for c in rows {
		fmt.sbprintf(&b, `<li><a href="/data?q=%s">`, html.url_encode(c.name))
		html.avatar(&b, c.id, c.name)
		w(&b, `<span class="sr-text"><strong>`)
		html.write_highlighted(&b, c.name, trimmed)
		w(&b, `</strong><small>`)
		html.write_highlighted(&b, c.email, trimmed)
		w(&b, `</small></span>`)
		role_chip(&b, c.role)
		w(&b, `</a></li>`)
	}
	w(&b, `</ul></div>`)
	return strings.to_string(b)
}


@(private = "file")
role_options :: proc(b: ^strings.Builder, selected: m.Role) {
	names := m.ROLE_NAMES
	for name, r in names {
		sel := r == selected ? " selected" : ""
		fmt.sbprintf(b, `<option value="%s"%s>%s</option>`, name, sel, name)
	}
}


// ---- data page shell ----------------------------------------------------

data_page :: proc(p: contacts.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Data",
		"Data & CRUD",
		"A live table over a SQLite store: filter, sort and paginate, plus create, update and delete.",
	)

	// Filter + add form sit outside the swapped region so they survive a reload
	// of the table itself.
	w(&b, `<div class="toolbar">
    <form class="filter" role="search"`)
	html.behave(&b, .Search_Box)
	w(&b, `>`)
	html.icon(&b, "search")
	w(&b, `<input type="search" name="q" placeholder="Filter contacts…" autocomplete="off" value="`)
	esc(&b, p.q)
	w(&b, `" hx-get="/contacts" hx-trigger="keyup changed delay:300ms, search"
             hx-target="#contact-region" hx-swap="outerHTML">
    </form>
    <details class="add">
      <summary class="btn btn-primary">`)
	html.icon(&b, "plus")
	w(&b, `<span>New contact</span></summary>
      <form class="add-form card" hx-post="/contacts" hx-target="#contact-tbody" hx-swap="beforeend"
            hx-status:422="target:#add-error swap:innerHTML"`)
	html.behave(&b, .Reset_On_Success)
	w(&b, `>
        `)
	fmt.sbprintf(&b, `<input name="name" placeholder="Full name" required maxlength="%d" aria-label="Name">`, contacts.MAX_NAME)
	fmt.sbprintf(&b, `<input name="email" type="email" placeholder="email@example.dev" required maxlength="%d" aria-label="Email">`, contacts.MAX_EMAIL)
	w(&b, `
        <select name="role" aria-label="Role">`)
	role_options(&b, .Engineer)
	w(&b, `</select>
        <button class="btn btn-accent" type="submit">Add</button>
        <p class="field-msg form-error" id="add-error" role="alert"></p>
      </form>
    </details>
  </div>`)

	w(&b, region(p))
	return strings.to_string(b)
}


status_badge :: proc(b: ^strings.Builder, s: m.Status) {
	names := m.STATUS_NAMES
	cls: string
	switch s {
	case .Active:   cls = "ok"
	case .Invited:  cls = "warn"
	case .Disabled: cls = "mute"
	}
	fmt.sbprintf(b, `<span class="badge badge-%s"><i class="dot"></i>%s</span>`, cls, names[s])
}

role_chip :: proc(b: ^strings.Builder, r: m.Role) {
	names := m.ROLE_NAMES
	fmt.sbprintf(b, `<span class="chip chip-r%d">%s</span>`, int(r), names[r])
}

