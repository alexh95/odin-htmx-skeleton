package audit_views

// ---- audit's views: the filter, the table and its rows -------------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import audit ".."
import m "../models"

w :: html.w
esc :: html.esc

// The page: the filter (a plain GET, so a filtered view is a link), the export of what it
// shows, and the first page of rows.
page :: proc(b: ^strings.Builder, f: m.Filter, entries: []m.Entry, kept: bool) {
	if !kept {
		w(b, `<section class="block"><p class="muted audit-memory">This build keeps no audit table: each entry is one <code>mod=audit</code> line in the process's log.</p></section>`)
		return
	}
	w(b, `<section class="block"><form class="audit-filter card" action="/admin/audit" method="get">`)
	fmt.sbprintf(b, `<label class="field"><span>Actor</span><input name="actor" maxlength="%d" placeholder="any" value="`, audit.MAX_FILTER)
	esc(b, f.actor)
	fmt.sbprintf(b, `"></label><label class="field"><span>Action</span><input name="action" maxlength="%d" placeholder="any, or a prefix: accounts." value="`, audit.MAX_FILTER)
	esc(b, f.action)
	w(b, `"></label><button class="btn btn-primary" type="submit">Filter</button>`)
	// hx-download saves the answer (its Content-Disposition is an attachment) instead of swapping it.
	w(b, `<button class="btn btn-outline" type="button" hx-get="`)
	esc(b, url(f, "/admin/audit/export", 0))
	w(b, `">Export CSV</button></form></section>`)
	w(b, `<section class="block"><table class="table audit-table"><thead><tr><th>When (UTC)</th><th>Actor</th><th>Action</th><th>Target</th><th>Reason</th><th>Client</th></tr></thead><tbody id="audit-rows">`)
	if len(entries) == 0 { w(b, `<tr class="audit-empty"><td colspan="6" class="muted">No entries.</td></tr>`) }
	rows(b, f, entries)
	w(b, `</tbody></table></section>`)
}

// A page of rows; a full page ends with the row that asks for the next one when it comes into view.
rows :: proc(b: ^strings.Builder, f: m.Filter, entries: []m.Entry) {
	for e in entries {
		fmt.sbprintf(b, `<tr class="audit-row" id="audit-%d"><td>%s</td><td>`, e.id, audit.stamp(e.at))
		esc(b, e.actor.name if e.actor.name != "" else "—")
		w(b, `</td><td><code>`)
		esc(b, e.action)
		w(b, `</code></td><td>`)
		esc(b, e.target.kind)
		if e.target.id != 0 { fmt.sbprintf(b, ` #%d`, e.target.id) }
		w(b, `</td><td>`)
		esc(b, e.reason)
		w(b, `</td><td><code>`)
		esc(b, e.actor.client[:min(len(e.actor.client), 8)])
		w(b, `</code></td></tr>`)
	}
	if len(entries) == f.limit && f.limit > 0 {
		w(b, `<tr class="audit-more" hx-get="`)
		esc(b, url(f, "/admin/audit/rows", entries[len(entries) - 1].id))
		w(b, `" hx-trigger="intersect once" hx-swap="outerHTML"><td colspan="6" class="muted">Loading…</td></tr>`)
	}
}

// The filter as a query on `path`, from `before` (0: the newest).
url :: proc(f: m.Filter, path: string, before: i64) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, path)
	strings.write_string(&b, "?actor=")
	strings.write_string(&b, html.url_encode(f.actor))
	strings.write_string(&b, "&action=")
	strings.write_string(&b, html.url_encode(f.action))
	if before > 0 { fmt.sbprintf(&b, "&before=%d", before) }
	return strings.to_string(b)
}
