package views
import "../services"
import "../models"

import "core:fmt"
import "core:strings"

// ---- page bodies (components / forms / data) ----------------------------
//
// These build the static structure of each page. The interactive bits hang off
// HTMX attributes that point at the fragment handlers in controllers.odin.

@(private = "file")
section_open :: proc(b: ^strings.Builder, title, desc: string) {
	fmt.sbprintf(
		b,
		`<section class="block"><div class="block-head"><h2>%s</h2><p class="muted">%s</p></div>`,
		title,
		desc,
	)
}

@(private = "file")
role_options :: proc(b: ^strings.Builder, selected: models.Role) {
	names := models.ROLE_NAMES
	for name, r in names {
		sel := r == selected ? " selected" : ""
		fmt.sbprintf(b, `<option value="%s"%s>%s</option>`, name, sel, name)
	}
}

// ---- components gallery -------------------------------------------------

view_components :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Library",
		"Components",
		"The everyday controls — buttons, badges, overlays, tabs — each styled once and reused everywhere.",
	)

	view_showroom(&b)

	// Buttons
	section_open(&b, "Buttons", "Variants and states, all one .btn with a modifier.")
	w(&b, `<div class="demo row">
    <button class="btn btn-primary">Primary</button>
    <button class="btn btn-accent">Accent</button>
    <button class="btn btn-outline">Outline</button>
    <button class="btn btn-ghost">Ghost</button>
    <button class="btn btn-danger">Danger</button>
    <button class="btn btn-primary" disabled>Disabled</button>
    <button class="btn btn-primary btn-loading"><span class="spinner"></span>Working…</button>
    <button class="icon-btn" aria-label="Icon button">`)
	icon(&b, "bell")
	w(&b, `</button>
  </div></section>`)

	// Badges, chips, tags
	section_open(&b, "Badges, chips & tags", "Status pills and categorical chips.")
	w(&b, `<div class="demo row">`)
	status_badge_demo(&b)
	w(&b, `<span class="chip chip-r0">Engineer</span><span class="chip chip-r1">Designer</span><span class="chip chip-r2">Manager</span>
    <span class="tag">v2.1</span><span class="tag tag-new">new</span>
    <span class="count">7<i>unread</i></span>
  </div></section>`)

	// Avatars
	section_open(&b, "Avatars", "Initials with a stable per-identity hue.")
	w(&b, `<div class="demo row"><div class="avatar-stack">`)
	demo := []models.Contact {
		{id = 1, name = "Ada Lovelace"},
		{id = 5, name = "Linus Torvalds"},
		{id = 9, name = "Grace Hopper"},
		{id = 14, name = "Tim Berners-Lee"},
	}
	for c in demo {avatar(&b, c)}
	w(&b, `<span class="avatar avatar-more">+9</span></div></div></section>`)

	// Progress & meters
	section_open(&b, "Progress & meters", "Determinate bars, a ring and an indeterminate spinner.")
	w(&b, `<div class="demo col">
    <div class="meter lg"><i style="width:72%"></i></div>
    <div class="meter lg meter-accent"><i style="width:46%"></i></div>
    <div class="row center">
      <div class="ring" style="--p:68"><span>68%</span></div>
      <span class="spinner spinner-lg"></span>
      <div class="bar-indeterminate"><i></i></div>
    </div>
  </div></section>`)

	// Inputs preview
	section_open(&b, "Inputs", "The raw fields, themed. Full forms live on the Forms page.")
	w(&b, `<div class="demo grid-3">
    <label class="field"><span>Text</span><input placeholder="Type here…"></label>
    <label class="field"><span>Select</span><select><option>One</option><option>Two</option></select></label>
    <label class="field"><span>Range</span><input type="range" value="60"></label>
    <label class="field"><span>Switch</span><span class="toggle"><input type="checkbox" checked><i></i></span></label>
    <label class="field"><span>Checkbox</span><span class="check"><input type="checkbox" checked><i></i> Subscribe</span></label>
    <label class="field"><span>Tooltip</span><button class="btn btn-outline" data-tip="Rendered with one ::after">Hover me</button></label>
  </div></section>`)

	// Tabs (HTMX)
	section_open(&b, "Tabs", "Panels fetched from the server on demand.")
	w(&b, `<div class="tabs">
    <div class="tablist" role="tablist">
      <button class="tab" role="tab" aria-selected="true" onclick="selectTab(this)" hx-get="/ui/tab/overview" hx-target="#tabpanel">Overview</button>
      <button class="tab" role="tab" onclick="selectTab(this)" hx-get="/ui/tab/activity" hx-target="#tabpanel">Activity</button>
      <button class="tab" role="tab" onclick="selectTab(this)" hx-get="/ui/tab/security" hx-target="#tabpanel">Security</button>
    </div>
    <div id="tabpanel" class="tabpanel" role="tabpanel">`)
	w(&b, tab_panel("overview"))
	w(&b, `</div>
  </div></section>`)

	// Accordion (native details/summary)
	section_open(&b, "Accordion", "Built on &lt;details&gt; — semantic and keyboard-friendly.")
	w(&b, `<div class="demo col accordion">`)
	acc_item(&b, "What is HTMX doing here?", "Every interactive panel on this page is a server fragment swapped in over a single request. No client state, no build step.", true)
	acc_item(&b, "Where does the markup come from?", "Odin procedures write HTML into a string builder. A component is just a proc — this accordion item is one.", false)
	acc_item(&b, "Is the data real?", "It is a real SQLite store, seeded at boot. Create and delete on the Data page mutate it live.", false)
	w(&b, `</div></section>`)

	// Overlays + toasts
	section_open(&b, "Overlays & toasts", "Dialog, drawer and notifications — opened and dismissed over HTMX.")
	w(&b, `<div class="demo row">
    <button class="btn btn-primary" hx-get="/ui/modal" hx-target="#overlay" hx-swap="innerHTML">Open dialog</button>
    <button class="btn btn-outline" hx-get="/ui/drawer" hx-target="#overlay" hx-swap="innerHTML">Open drawer</button>
    <button class="btn btn-accent" hx-get="/ui/toast?kind=success" hx-target="#toasts" hx-swap="beforeend">Success toast</button>
    <button class="btn btn-ghost" hx-get="/ui/toast?kind=error" hx-target="#toasts" hx-swap="beforeend">Error toast</button>
  </div></section>`)

	return strings.to_string(b)
}

@(private = "file")
status_badge_demo :: proc(b: ^strings.Builder) {
	w(b, `<span class="badge badge-ok"><i class="dot"></i>Active</span>`)
	w(b, `<span class="badge badge-warn"><i class="dot"></i>Invited</span>`)
	w(b, `<span class="badge badge-mute"><i class="dot"></i>Disabled</span>`)
}

@(private = "file")
acc_item :: proc(b: ^strings.Builder, q, a: string, open: bool) {
	op := open ? " open" : ""
	fmt.sbprintf(b, `<details class="acc"%s><summary><span>%s</span>`, op, q)
	icon(b, "plus")
	fmt.sbprintf(b, `</summary><div class="acc-body"><p>%s</p></div></details>`, a)
}

// ---- forms --------------------------------------------------------------

view_forms :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Forms",
		"Forms & validation",
		"A real form wired to the same service layer. The email field validates as you type; submit creates a contact.",
	)

	// data-reset-on-success: app.js resets the form after its OWN successful submit.
	// Scoped there to this form's request (ctx.sourceElement), so the email field's
	// inline validation can't trip the reset and wipe what the user just typed.
	w(&b, `<form class="form card" hx-post="/forms/submit" hx-target="#form-result" hx-swap="innerHTML"
        data-reset-on-success>
  <div class="form-grid">
    <label class="field">
      <span>Full name</span>
      <input name="name" placeholder="Grace Hopper" required>
    </label>
    <label class="field">
      <span>Email</span>
      <input name="email" type="email" placeholder="grace@example.dev" autocomplete="off"
             hx-post="/validate/email" hx-trigger="change, keyup changed delay:400ms"
             hx-target="next .field-msg" hx-swap="innerHTML">
      <p class="field-msg"></p>
    </label>
    <label class="field">
      <span>Role</span>
      <select name="role">`)
	role_options(&b, .Engineer)
	w(&b, `</select>
    </label>
    <label class="field">
      <span>Engagement <output class="out">60</output></span>
      <input type="range" name="score" min="0" max="100" value="60"
             oninput="this.previousElementSibling.querySelector('.out').value=this.value">
    </label>
    <fieldset class="field span-2">
      <legend>Status</legend>
      <div class="radios">
        <label class="radio"><input type="radio" name="status" value="Active" checked><i></i>Active</label>
        <label class="radio"><input type="radio" name="status" value="Invited"><i></i>Invited</label>
        <label class="radio"><input type="radio" name="status" value="Disabled"><i></i>Disabled</label>
      </div>
    </fieldset>
    <label class="field span-2 inline">
      <span class="toggle"><input type="checkbox" name="notify" checked><i></i></span>
      <span>Email me about account activity</span>
    </label>
    <label class="field span-2">
      <span>Notes</span>
      <textarea name="notes" rows="3" placeholder="Anything worth remembering…"></textarea>
    </label>
  </div>
  <div class="form-actions">
    <button class="btn btn-primary" type="submit">`)
	icon(&b, "check")
	w(&b, `<span>Create contact</span></button>
    <button class="btn btn-ghost" type="reset">Reset</button>
  </div>
  <div id="form-result" class="form-result"></div>
</form>`)
	return strings.to_string(b)
}

// ---- data page shell ----------------------------------------------------

view_data :: proc(p: services.Page) -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Data",
		"Data &amp; CRUD",
		"A live table over a SQLite store: filter, sort and paginate, plus create, update and delete.",
	)

	// Filter + add form sit outside the swapped region so they survive a reload
	// of the table itself.
	w(&b, `<div class="toolbar">
    <form class="filter" role="search" onsubmit="return false">`)
	icon(&b, "search")
	w(&b, `<input type="search" name="q" placeholder="Filter contacts…" autocomplete="off" value="`)
	esc(&b, p.q)
	w(&b, `" hx-get="/contacts" hx-trigger="keyup changed delay:300ms, search"
             hx-target="#contact-region" hx-swap="outerHTML">
    </form>
    <details class="add">
      <summary class="btn btn-primary">`)
	icon(&b, "plus")
	w(&b, `<span>New contact</span></summary>
      <form class="add-form card" hx-post="/contacts" hx-target="#contact-tbody" hx-swap="beforeend"
            data-reset-on-success>
        <input name="name" placeholder="Full name" required aria-label="Name">
        <input name="email" type="email" placeholder="email@example.dev" required aria-label="Email">
        <select name="role" aria-label="Role">`)
	role_options(&b, .Engineer)
	w(&b, `</select>
        <button class="btn btn-accent" type="submit">Add</button>
      </form>
    </details>
  </div>`)

	w(&b, view_contacts_region(p))
	return strings.to_string(b)
}

// ---- about --------------------------------------------------------------

view_about :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"About",
		"About this project",
		"A starter skeleton for simple, server-rendered websites — Odin + HTMX + SQLite in one self-contained binary.",
	)

	w(&b, `<section class="block"><article class="card about">`)
	w(&b, `<p class="about-lede">This is a <strong>starter skeleton</strong>: an <a href="https://odin-lang.org" target="_blank" rel="noopener">Odin</a> backend that renders HTML, wired up with <a href="https://htmx.org" target="_blank" rel="noopener">HTMX</a> over a <a href="https://sqlite.org" target="_blank" rel="noopener">SQLite</a> store, served as a single statically-linked binary.</p>`)
	w(&b, `<p class="muted">The contacts &amp; events console you have been clicking through is the <em>worked example</em> that proves the patterns — not the product. Clone the repository, strip the demo, and build your own thing on the same scaffolding: the layered architecture, the data layer, the theme system, and the build / CI / deploy / test harness.</p>`)
	w(&b, `<div class="about-stack"><span class="tag">Odin</span><span class="tag">HTMX 4</span><span class="tag">SQLite</span><span class="tag">single binary</span><span class="tag">no build step</span></div>`)
	// BRAND_REPO is a developer-set constant (see brand.odin), not user input.
	fmt.sbprintf(&b, `<a class="btn btn-primary about-cta" href="%s" target="_blank" rel="noopener">`, BRAND_REPO)
	icon(&b, "github")
	w(&b, `<span>View on GitHub</span></a>`)
	w(&b, `</article></section>`)
	return strings.to_string(b)
}
