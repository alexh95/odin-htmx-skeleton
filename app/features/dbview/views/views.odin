package dbview_views

// ---- dbview's views: the form and a result -----------------------------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import dbview ".."
import m "../models"

w :: html.w
esc :: html.esc

// The form: the query stays as typed after a run (the answer goes below it, not over it).
page :: proc(b: ^strings.Builder) {
	w(b, `<section class="block"><form class="card dbview-form" hx-post="/admin/dbview" hx-target="#dbview-result" hx-swap="innerHTML">`)
	fmt.sbprintf(b, `<label class="field"><span>SQL, one statement that only reads</span><textarea id="dbview-sql" name="sql" rows="6" maxlength="%d" required spellcheck="false">SELECT name, type FROM sqlite_schema ORDER BY name</textarea></label>`, dbview.MAX_SQL)
	fmt.sbprintf(b, `<p class="muted">Read only, on a connection of its own: never the writer's. At most %d rows and %d s; every query is audited.</p>`, dbview.MAX_ROWS, i64(dbview.BUDGET / 1e9))
	w(b, `<button class="btn btn-primary" type="submit">Run</button></form></section>`)
	w(b, `<section class="block"><div id="dbview-result" aria-live="polite"></div></section>`)
}

// A result: its table, how many rows and how long, and what stopped it, if anything did.
result :: proc(b: ^strings.Builder, r: m.Result, problem: string) {
	if problem != "" {
		w(b, `<p class="field-msg form-error dbview-problem">`)
		esc(b, problem)
		w(b, `</p>`)
	}
	if len(r.columns) == 0 { return }
	fmt.sbprintf(b, `<p class="muted dbview-meta">%d row%s%s in %.1f ms</p>`, len(r.rows), "" if len(r.rows) == 1 else "s", ", and more not shown" if r.cut else "", r.ms)
	w(b, `<div class="table-wrap"><table class="table dbview-table"><thead><tr>`)
	for c in r.columns {
		w(b, `<th>`)
		esc(b, c)
		w(b, `</th>`)
	}
	w(b, `</tr></thead><tbody>`)
	for row in r.rows {
		w(b, `<tr>`)
		for v in row {
			w(b, `<td>`)
			esc(b, v)
			w(b, `</td>`)
		}
		w(b, `</tr>`)
	}
	w(b, `</tbody></table></div>`)
}
