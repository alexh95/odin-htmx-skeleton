package gallery_views

// ---- gallery: the views -----------------------------------------------------------------------
//
// The skeleton's component gallery and forms page. The forms page builds a
// contact: its limits and role labels come from the contacts domain through
// gallery_web, since a view imports only its own feature and platform/html.

import "core:fmt"
import "core:strings"

import "../../../platform/html"

w :: html.w
esc :: html.esc
page_head :: html.page_head

// What the forms page shows of the contact it creates.
Contact_Form :: struct {
	roles:                         []string, // labels, the first selected
	max_name, max_email, max_notes: int,
}

@(private = "file")
role_options :: proc(b: ^strings.Builder, roles: []string) {
	for name, i in roles {
		fmt.sbprintf(b, `<option value="%s"%s>%s</option>`, name, " selected" if i == 0 else "", name)
	}
}

// Both are text.
@(private = "file")
section_open :: proc(b: ^strings.Builder, title, desc: string) {
	w(b, `<section class="block"><div class="block-head"><h2>`)
	esc(b, title)
	w(b, `</h2><p class="muted">`)
	esc(b, desc)
	w(b, `</p></div>`)
}


// ---- components gallery -------------------------------------------------

components_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Library",
		"Components",
		"The everyday controls — buttons, badges, overlays, tabs — each styled once and reused everywhere.",
	)

	html.theme_showroom(&b)

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
	html.icon(&b, "bell")
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
	demo := []struct {
		id:   i64,
		name: string,
	}{{1, "Ada Lovelace"}, {5, "Linus Torvalds"}, {9, "Grace Hopper"}, {14, "Tim Berners-Lee"}}
	for c in demo {html.avatar(&b, c.id, c.name)}
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
    <label class="field"><span>Range</span><input type="range" value="60"`)
	html.behave(&b, .Range_Fill)
	w(&b, `></label>
    <label class="field"><span>Switch</span><span class="toggle"><input type="checkbox" checked><i></i></span></label>
    <label class="field"><span>Checkbox</span><span class="check"><input type="checkbox" checked><i></i> Subscribe</span></label>
    <label class="field"><span>Tooltip</span><button class="btn btn-outline" data-tip="Rendered with one ::after">Hover me</button></label>
  </div></section>`)

	// Tabs (HTMX)
	section_open(&b, "Tabs", "Panels fetched from the server on demand.")
	w(&b, `<div class="tabs">
    <div class="tablist" role="tablist"`)
	html.behave(&b, .Tabs)
	w(&b, `>
      <button class="tab" role="tab" aria-selected="true" hx-get="/ui/tab/overview" hx-target="#tabpanel">Overview</button>
      <button class="tab" role="tab" aria-selected="false" hx-get="/ui/tab/activity" hx-target="#tabpanel">Activity</button>
      <button class="tab" role="tab" aria-selected="false" hx-get="/ui/tab/security" hx-target="#tabpanel">Security</button>
    </div>
    <div id="tabpanel" class="tabpanel" role="tabpanel">`)
	w(&b, tab_panel("overview"))
	w(&b, `</div>
  </div></section>`)

	// Accordion (native details/summary)
	section_open(&b, "Accordion", "Built on <details> — semantic and keyboard-friendly.")
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
	w(b, open ? `<details class="acc" open><summary><span>` : `<details class="acc"><summary><span>`)
	esc(b, q)
	w(b, `</span>`)
	html.icon(b, "plus")
	w(b, `</summary><div class="acc-body"><p>`)
	esc(b, a)
	w(b, `</p></div></details>`)
}

// ---- forms --------------------------------------------------------------

forms_page :: proc(f: Contact_Form) -> string {
	b := strings.builder_make(context.temp_allocator)
	page_head(
		&b,
		"Forms",
		"Forms & validation",
		"A real form wired to the same service layer. The email field validates as you type; submit creates a contact.",
	)

	// ResetOnSuccess: the form resets after its OWN successful submit, scoped to
	// this form's request (ctx.sourceElement), so the email field's inline
	// validation can't trip the reset and wipe what the user just typed. A refused
	// submit is a 422, which lands in #form-result like a success and leaves the
	// fields alone, so it needs no hx-status of its own.
	w(&b, `<form class="form card" hx-post="/forms/submit" hx-target="#form-result" hx-swap="innerHTML"`)
	html.behave(&b, .Reset_On_Success)
	w(&b, `>
  <div class="form-grid">
    <label class="field">
      <span>Full name</span>
      `)
	// maxlength mirrors the server's limits, so the browser stops at the same place.
	fmt.sbprintf(&b, `<input name="name" placeholder="Grace Hopper" required maxlength="%d">`, f.max_name)
	w(&b, `
    </label>
    <label class="field">
      <span>Email</span>
      `)
	fmt.sbprintf(&b, `<input name="email" type="email" placeholder="grace@example.dev" autocomplete="off" required maxlength="%d"`, f.max_email)
	w(&b, `
             hx-post="/validate/email" hx-trigger="change, keyup changed delay:400ms"
             hx-target="next .field-msg" hx-swap="innerHTML">
      <p class="field-msg"></p>
    </label>
    <label class="field">
      <span>Role</span>
      <select name="role">`)
	role_options(&b, f.roles)
	w(&b, `</select>
    </label>
    <label class="field">
      <span>Engagement <output class="out">60</output></span>
      <input type="range" name="score" min="0" max="100" value="60"`)
	html.behave(&b, .Range_Fill)
	w(&b, `>
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
      `)
	fmt.sbprintf(&b, `<textarea name="notes" rows="3" maxlength="%d" placeholder="Anything worth remembering…"></textarea>`, f.max_notes)
	w(&b, `
    </label>
  </div>
  <div class="form-actions">
    <button class="btn btn-primary" type="submit">`)
	html.icon(&b, "check")
	w(&b, `<span>Create contact</span></button>
    <button class="btn btn-ghost" type="reset">Reset</button>
  </div>
  <div id="form-result" class="form-result"></div>
</form>`)
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

modal :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	// The backdrop deliberately has no close handler: a stray click outside the
	// dialog shouldn't discard whatever the user has typed. Dismissal is explicit
	// — the × or Cancel.
	w(&b, `<div class="backdrop">
  <div class="modal" role="dialog" aria-modal="true" aria-labelledby="m-title">
    <header class="modal-head"><h2 id="m-title">Invite a teammate</h2>
      <button class="icon-btn" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:200ms">`)
	html.icon(&b, "plus")
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

drawer :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="backdrop" hx-get="/ui/clear" hx-trigger="click from:self" hx-target="#overlay" hx-swap="innerHTML swap:240ms">
  <aside class="drawer" role="dialog" aria-modal="true" aria-label="Settings">
    <header class="drawer-head"><h2>Workspace</h2>
      <button class="icon-btn" aria-label="Close" hx-get="/ui/clear" hx-target="#overlay" hx-swap="innerHTML swap:240ms">`)
	html.icon(&b, "plus")
	w(&b, `</button></header>
    <nav class="drawer-nav">
      <a href="#" class="drawer-link">`)
	html.icon(&b, "grid")
	w(&b, `<span>General</span></a>
      <a href="#" class="drawer-link">`)
	html.icon(&b, "users")
	w(&b, `<span>Members</span></a>
      <a href="#" class="drawer-link">`)
	html.icon(&b, "bell")
	w(&b, `<span>Notifications</span></a>
    </nav>
    <p class="muted drawer-foot">Slides in from the edge with a spring curve, dismissed by tapping the backdrop.</p>
  </aside>
</div>`)
	return strings.to_string(b)
}


form_result :: proc(id: i64, name, email: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="result-ok">`)
	html.icon(&b, "check")
	w(&b, `<div><strong>Contact created</strong><p>`)
	esc(&b, name)
	w(&b, ` · `)
	esc(&b, email)
	fmt.sbprintf(&b, ` · saved as #%d</p></div></div>`, id)
	return strings.to_string(b)
}

form_errors :: proc(msgs: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="result-err"><strong>Please fix the following:</strong><ul>`)
	for msg in msgs {
		w(&b, `<li>`)
		esc(&b, msg)
		w(&b, `</li>`)
	}
	w(&b, `</ul></div>`)
	return strings.to_string(b)
}
