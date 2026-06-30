package views
import "../services"
import "../models"

import "core:fmt"
import "core:strings"

// ---- HTMX fragments -----------------------------------------------------
//
// Each proc returns the HTML for one swap target. They are the seam between
// the controllers (which decide what to render) and the page bodies (which
// declare where it lands). Fragments never wrap themselves in the layout.

// The whole swappable table: header controls, sortable columns, rows, and the
// pager. Sort and page links carry the current query so state is encoded in
// the request, not stashed on the client.
view_contacts_region :: proc(p: services.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div id="contact-region" class="card table-card"><div class="table-meta"><div class="table-filters">`)
	filter_chip(&b, p, "all", "All")
	for name in models.STATUS_NAMES {
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
		icon(&b, "search")
		w(&b, `<p>No contacts match that filter.</p></div></td></tr>`)
	} else {
		for c in p.rows {
			view_contact_row(&b, c, false)
		}
	}
	w(&b, `</tbody></table></div>`)

	pager(&b, p)
	w(&b, `</div>`)
	return strings.to_string(b)
}

// One column header. Shows the active direction and links to the next state
// (asc -> desc -> asc) via services.next_sort.
// A status quick-filter chip. "all" clears the filter; the active chip is marked.
@(private = "file")
filter_chip :: proc(b: ^strings.Builder, p: services.Page, value, label: string) {
	active := value == "all" ? (p.status == "" || p.status == "all") : (p.status == value)
	q := value == "all" ? "" : value
	fmt.sbprintf(
		b,
		`<button class="chip-filter%s" hx-get="/contacts?q=%s&status=%s&sort=%s&page=1" hx-target="#contact-region" hx-swap="outerHTML">%s</button>`,
		active ? " is-active" : "",
		url_encode(p.q),
		url_encode(q),
		url_encode(p.sort),
		label,
	)
}

@(private = "file")
sort_th :: proc(b: ^strings.Builder, p: services.Page, column, label: string) {
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
		url_encode(p.q),
		url_encode(p.status),
		services.next_sort(p.sort, column),
		label,
	)
}

@(private = "file")
pager :: proc(b: ^strings.Builder, p: services.Page) {
	if p.total_pages <= 1 {
		return
	}
	w(b, `<nav class="pager" aria-label="Pagination">`)
	page_btn(b, p, p.page - 1, "‹ Prev", p.page <= 1)
	for n in 1 ..= p.total_pages {
		if n == p.page {
			fmt.sbprintf(b, `<button class="page is-current" aria-current="page">%d</button>`, n)
			continue
		}
		fmt.sbprintf(
			b,
			`<button class="page" hx-get="/contacts?q=%s&status=%s&sort=%s&page=%d" hx-target="#contact-region" hx-swap="outerHTML">%d</button>`,
			url_encode(p.q),
			url_encode(p.status),
			url_encode(p.sort),
			n,
			n,
		)
	}
	page_btn(b, p, p.page + 1, "Next ›", p.page >= p.total_pages)
	w(b, `</nav>`)
}

@(private = "file")
page_btn :: proc(b: ^strings.Builder, p: services.Page, target: int, label: string, disabled: bool) {
	if disabled {
		fmt.sbprintf(b, `<button class="page" disabled>%s</button>`, label)
		return
	}
	fmt.sbprintf(
		b,
		`<button class="page" hx-get="/contacts?q=%s&status=%s&sort=%s&page=%d" hx-target="#contact-region" hx-swap="outerHTML">%s</button>`,
		url_encode(p.q),
		url_encode(p.status),
		url_encode(p.sort),
		target,
		label,
	)
}

// A single contact row. `fresh` adds the entrance highlight used when a row is
// appended after a create. To refresh the row behind the detail drawer the
// controller wraps this in an <hx-partial> targeting #contact-<id> (see
// contacts_update) — no per-row OOB attribute needed.
view_contact_row :: proc(b: ^strings.Builder, c: models.Contact, fresh: bool) {
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
	avatar(b, c)
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
	icon(b, "cycle")
	fmt.sbprintf(
		b,
		`</button><button class="icon-btn danger" title="Delete" hx-delete="/contacts/%d" hx-target="#contact-%d" hx-swap="outerHTML swap:220ms" hx-confirm="Delete this contact?">`,
		c.id,
		c.id,
	)
	icon(b, "trash")
	w(b, `</button></td></tr>`)
}

// The contact detail drawer — the drilldown past the table row. `view_contact_detail`
// returns the backdrop + aside (loaded into #overlay on open); the `_frag` variant
// returns just the aside, for in-place swaps (edit toggle / save / cycle) that target
// `.drawer-detail` so the backdrop doesn't re-animate.
view_contact_detail :: proc(c: models.Contact, timeline: []models.Interaction, related: []models.Contact) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="backdrop" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	detail_aside(&b, c, timeline, related, false, false)
	w(&b, `</div>`)
	return strings.to_string(b)
}

view_contact_detail_frag :: proc(c: models.Contact, timeline: []models.Interaction, related: []models.Contact, editing: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	detail_aside(&b, c, timeline, related, editing, true)
	return strings.to_string(b)
}

@(private = "file")
detail_aside :: proc(b: ^strings.Builder, c: models.Contact, timeline: []models.Interaction, related: []models.Contact, editing, static_anim: bool) {
	// drawer-static skips the slide-in so in-place swaps don't re-animate.
	fmt.sbprintf(
		b,
		`<aside class="drawer drawer-detail%s" role="dialog" aria-modal="true" aria-label="Contact detail" onclick="event.stopPropagation()"><header class="drawer-head detail-head">`,
		static_anim ? " drawer-static" : "",
	)
	avatar(b, c)
	w(b, `<div class="detail-id"><h2>`)
	esc(b, c.name)
	w(b, `</h2><p class="muted">`)
	esc(b, c.email)
	w(b, `</p></div><button class="icon-btn detail-close" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	icon(b, "plus")
	w(b, `</button></header>`)
	if editing {
		detail_edit_form(b, c)
	} else {
		detail_view_body(b, c, timeline, related)
	}
	w(b, `</aside>`)
}

@(private = "file")
detail_view_body :: proc(b: ^strings.Builder, c: models.Contact, timeline: []models.Interaction, related: []models.Contact) {
	rn := models.ROLE_NAMES
	w(b, `<div class="detail-body"><div class="detail-actions">`)
	fmt.sbprintf(b, `<button class="btn btn-outline btn-sm" hx-get="/contacts/%d?edit=1&frag=1" hx-target="closest .drawer-detail" hx-swap="outerHTML">`, c.id)
	icon(b, "edit")
	w(b, `<span>Edit</span></button>`)
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm" hx-post="/contacts/%d" hx-vals='`, c.id)
	w(b, `{"action":"cycle","view":"detail","frag":"1"}`)
	w(b, `' hx-target="closest .drawer-detail" hx-swap="outerHTML">`)
	icon(b, "cycle")
	w(b, `<span>Cycle</span></button>`)
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm danger" hx-delete="/contacts/%d?from=drawer" hx-target="#overlay" hx-swap="innerHTML swap:240ms" hx-confirm="Delete this contact?">`, c.id)
	icon(b, "trash")
	w(b, `<span>Delete</span></button></div><div class="detail-meta">`)
	role_chip(b, c.role)
	status_badge(b, c.status)
	fmt.sbprintf(b, `<span class="detail-score"><small class="muted">Engagement</small><div class="meter"><i style="width:%d%%"></i></div><strong>%d / 100</strong></span><span class="detail-rid">#%d</span>`, c.score, c.score, c.id)
	w(b, `</div><section class="detail-section"><h3>Activity</h3>`)
	if len(timeline) == 0 {
		w(b, `<p class="muted detail-empty">No interactions yet.</p>`)
	} else {
		w(b, `<ol class="timeline">`)
		for it in timeline {
			w(b, `<li><span class="tl-dot">`)
			icon(b, interaction_icon(it.kind))
			w(b, `</span><div class="tl-body"><strong>`)
			interaction_label(b, it)
			w(b, `</strong><small>`)
			if it.note != "" {
				esc(b, it.note)
				w(b, ` · `)
			}
			esc(b, services.time_ago(it.at))
			w(b, `</small></div></li>`)
		}
		w(b, `</ol>`)
	}
	w(b, `</section>`)
	if len(related) > 0 {
		fmt.sbprintf(b, `<section class="detail-section"><h3>Also in %s</h3><div class="related-list">`, rn[c.role])
		for r in related {
			fmt.sbprintf(b, `<button class="related-item" type="button" hx-get="/contacts/%d" hx-target="#overlay" hx-swap="innerHTML">`, r.id)
			avatar(b, r)
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
interaction_label :: proc(b: ^strings.Builder, it: models.Interaction) {
	names := models.EVENT_KIND_NAMES
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
who_link :: proc(b: ^strings.Builder, id: int, name: string) {
	fmt.sbprintf(b, `<button class="tl-who" type="button" hx-get="/contacts/%d" hx-target="#overlay" hx-swap="innerHTML">`, id)
	esc(b, name)
	w(b, `</button>`)
}

@(private = "file")
interaction_icon :: proc(kind: models.Event_Kind) -> string {
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

@(private = "file")
detail_edit_form :: proc(b: ^strings.Builder, c: models.Contact) {
	rn := models.ROLE_NAMES
	sn := models.STATUS_NAMES
	fmt.sbprintf(b, `<form class="detail-body detail-edit" hx-post="/contacts/%d" hx-target="closest .drawer-detail" hx-swap="outerHTML"><input type="hidden" name="view" value="detail"><input type="hidden" name="frag" value="1"><label class="field"><span>Name</span><input name="name" value="`, c.id)
	esc(b, c.name)
	w(b, `" required></label><label class="field"><span>Email</span><input name="email" type="email" value="`)
	esc(b, c.email)
	w(b, `" required></label><label class="field"><span>Role</span><select name="role">`)
	for name, r in rn {
		fmt.sbprintf(b, `<option%s>%s</option>`, r == c.role ? " selected" : "", name)
	}
	w(b, `</select></label><label class="field"><span>Status</span><select name="status">`)
	for name, st in sn {
		fmt.sbprintf(b, `<option%s>%s</option>`, st == c.status ? " selected" : "", name)
	}
	w(b, `</select></label>`)
	fmt.sbprintf(b, `<label class="field"><span>Engagement <b>%d</b></span><input name="score" type="range" min="0" max="100" value="%d" oninput="this.previousElementSibling.querySelector('b').textContent=this.value"></label>`, c.score, c.score)
	w(b, `<div class="detail-actions"><button class="btn btn-primary btn-sm" type="submit">`)
	icon(b, "check")
	w(b, `<span>Save</span></button>`)
	fmt.sbprintf(b, `<button class="btn btn-ghost btn-sm" type="button" hx-get="/contacts/%d?frag=1" hx-target="closest .drawer-detail" hx-swap="outerHTML">Cancel</button></div></form>`, c.id)
}

// ---- search dropdown ----------------------------------------------------

view_search_results :: proc(q: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	trimmed := strings.trim_space(q)
	if trimmed == "" {
		return "" // empty target collapses the dropdown
	}

	rows := services.service_search(trimmed, services.SEARCH_LIMIT)
	if len(rows) == 0 {
		w(&b, `<div class="search-panel"><p class="search-empty">No matches for “`)
		esc(&b, trimmed)
		w(&b, `”.</p></div>`)
		return strings.to_string(b)
	}

	w(&b, `<div class="search-panel"><ul class="search-list">`)
	for c in rows {
		fmt.sbprintf(&b, `<li><a href="/data?q=%s">`, url_encode(c.name))
		avatar(&b, c)
		w(&b, `<span class="sr-text"><strong>`)
		write_highlighted(&b, c.name, trimmed)
		w(&b, `</strong><small>`)
		write_highlighted(&b, c.email, trimmed)
		w(&b, `</small></span>`)
		role_chip(&b, c.role)
		w(&b, `</a></li>`)
	}
	w(&b, `</ul></div>`)
	return strings.to_string(b)
}

// ---- tabs ---------------------------------------------------------------

tab_panel :: proc(name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	switch name {
	case "activity":
		w(&b, `<h3>Recent activity</h3><ul class="timeline">
      <li><span class="t-dot"></span><div><strong>Invite sent</strong><small>2 minutes ago</small></div></li>
      <li><span class="t-dot"></span><div><strong>Profile updated</strong><small>1 hour ago</small></div></li>
      <li><span class="t-dot"></span><div><strong>Joined the workspace</strong><small>yesterday</small></div></li>
    </ul>`)
	case "security":
		w(&b, `<h3>Security</h3><p class="muted">Two-factor authentication is enforced for every account in this workspace.</p>
    <label class="field span-2 inline"><span class="toggle"><input type="checkbox" checked><i></i></span><span>Require hardware keys</span></label>`)
	case: // overview
		w(&b, `<h3>Overview</h3><p class="muted">Panels are fetched per click and swapped into place. Switching tabs is one GET request, nothing more.</p>
    <div class="row"><div class="ring" style="--p:82"><span>82%</span></div><div class="ring" style="--p:54"><span>54%</span></div><div class="ring" style="--p:96"><span>96%</span></div></div>`)
	}
	return strings.to_string(b)
}

// ---- overlays -----------------------------------------------------------

view_modal :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	// The backdrop deliberately has no close handler: a stray click outside the
	// dialog shouldn't discard whatever the user has typed. Dismissal is explicit
	// — the × or Cancel.
	w(&b, `<div class="backdrop">
  <div class="modal" role="dialog" aria-modal="true" aria-labelledby="m-title">
    <header class="modal-head"><h2 id="m-title">Invite a teammate</h2>
      <button class="icon-btn" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:200ms">`)
	icon(&b, "plus")
	w(&b, `</button></header>
    <div class="modal-body">
      <p class="muted">This dialog was fetched from the server and removed the same way. The backdrop and the close button share one handler.</p>
      <label class="field"><span>Email</span><input type="email" placeholder="teammate@example.dev"></label>
    </div>
    <footer class="modal-foot">
      <button class="btn btn-ghost" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:200ms">Cancel</button>
      <button class="btn btn-primary" hx-get="/ui/toast?kind=success" hx-target="#toasts" hx-swap="beforeend">Send invite</button>
    </footer>
  </div>
</div>`)
	return strings.to_string(b)
}

view_drawer :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="backdrop" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">
  <aside class="drawer" role="dialog" aria-modal="true" aria-label="Settings" onclick="event.stopPropagation()">
    <header class="drawer-head"><h2>Workspace</h2>
      <button class="icon-btn" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	icon(&b, "plus")
	w(&b, `</button></header>
    <nav class="drawer-nav">
      <a href="#" class="drawer-link">`)
	icon(&b, "grid")
	w(&b, `<span>General</span></a>
      <a href="#" class="drawer-link">`)
	icon(&b, "users")
	w(&b, `<span>Members</span></a>
      <a href="#" class="drawer-link">`)
	icon(&b, "bell")
	w(&b, `<span>Notifications</span></a>
    </nav>
    <p class="muted drawer-foot">Slides in from the edge with a spring curve, dismissed by tapping the backdrop.</p>
  </aside>
</div>`)
	return strings.to_string(b)
}

// ---- toasts -------------------------------------------------------------

// A toast. `oob` makes it an out-of-band swap so a handler whose main target is
// elsewhere (a new table row, say) can still drop a toast into #toasts.
view_toast :: proc(kind, message: string, oob: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	ic, cls: string
	switch kind {
	case "error":   ic, cls = "bell", "toast-error"
	case "info":    ic, cls = "bell", "toast-info"
	case:           ic, cls = "check", "toast-success"
	}
	// For an out-of-band toast, htmx's positional swap (beforeend:#toasts)
	// appends the OOB element's *children* — so wrap the toast in a throwaway
	// carrier whose single child is the .toast that lands in #toasts.
	if oob {
		w(&b, `<div hx-swap-oob="beforeend:#toasts">`)
	}
	fmt.sbprintf(&b, `<div class="toast %s" role="status"><span class="toast-icon">`, cls)
	icon(&b, ic)
	w(&b, `</span><p>`)
	esc(&b, message)
	w(&b, `</p><button class="toast-x" aria-label="Dismiss" onclick="dismissToast(this)">×</button></div>`)
	if oob {
		w(&b, `</div>`)
	}
	return strings.to_string(b)
}

// ---- misc fragments -----------------------------------------------------

view_ping :: proc(now_ms: i64, rps: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="ping-ok">`)
	icon(&b, "check")
	fmt.sbprintf(
		&b,
		`<div><strong>200 OK</strong><small>uptime token %d · %d req/s synthetic</small></div></div>`,
		now_ms,
		rps,
	)
	return strings.to_string(b)
}

view_field_msg :: proc(ok: bool, message: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	cls := ok ? "ok" : "err"
	fmt.sbprintf(&b, `<span class="msg msg-%s">`, cls)
	esc(&b, message)
	w(&b, `</span>`)
	return strings.to_string(b)
}

view_form_result :: proc(c: models.Contact) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="result-ok">`)
	icon(&b, "check")
	w(&b, `<div><strong>Contact created</strong><p>`)
	esc(&b, c.name)
	w(&b, ` · `)
	esc(&b, c.email)
	fmt.sbprintf(&b, ` · saved as #%d</p></div></div>`, c.id)
	return strings.to_string(b)
}

view_form_errors :: proc(errs: []services.Field_Error) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="result-err"><strong>Please fix the following:</strong><ul>`)
	for e in errs {
		w(&b, `<li>`)
		esc(&b, e.msg)
		w(&b, `</li>`)
	}
	w(&b, `</ul></div>`)
	return strings.to_string(b)
}
