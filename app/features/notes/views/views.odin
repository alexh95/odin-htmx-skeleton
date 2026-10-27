package notes_views

// ---- notes: the views --------------------------------------------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import notes ".."
import m "../models"

w :: html.w
esc :: html.esc

// The add form and the newest notes, as a card (the home page shows it).
card :: proc(b: ^strings.Builder, list: []m.Note) {
	w(b, `<section class="block"><article class="card">`)
	// ResetOnSuccess clears the form after its own 2xx submit. A refused note (422)
	// or a server error (5xx) is routed by hx-status into the form's error slot
	// instead of the list, and leaves the input alone.
	w(b, `<form class="add-note" hx-post="/notes" hx-target="#note-list" hx-swap="afterbegin"`)
	html.behave(b, .Reset_On_Success)
	w(b, `
      hx-status:422="target:#note-error swap:innerHTML" hx-status:5xx="target:#note-error swap:innerHTML">`)
	fmt.sbprintf(b, `<input name="body" placeholder="Write a note…" required maxlength="%d" autocomplete="off" aria-label="Note">`, notes.MAX_NOTE)
	w(b, `<button class="btn btn-primary" type="submit">Add</button><p class="field-msg form-error" id="note-error" role="alert"></p></form>`)
	w(b, `<ul class="note-list" id="note-list">`)
	for n in list {
		li(b, n)
	}
	w(b, `</ul></article></section>`)
}

li :: proc(b: ^strings.Builder, n: m.Note) {
	w(b, `<li class="note"><span class="note-body">`)
	esc(b, n.body)
	w(b, `</span><small class="note-time">`)
	esc(b, html.time_ago(n.at))
	w(b, `</small></li>`)
}
