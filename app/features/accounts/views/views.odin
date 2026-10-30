package accounts_views

// ---- accounts' views: the sign-in form and the sessions list --------------------------------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import accounts ".."
import m "../models"

w :: html.w
esc :: html.esc

// The sign-in form. A refusal (422 wrong, 429 backed off or too many, 503 busy) lands in its
// error slot and leaves both fields as typed.
login_form :: proc(b: ^strings.Builder, next: string, insecure: bool) {
	w(b, `<section class="block"><form class="card login-form" hx-post="/login"
      hx-status:4xx="target:#login-error swap:innerHTML" hx-status:5xx="target:#login-error swap:innerHTML">`)
	fmt.sbprintf(b, `<label class="field"><span>Username</span><input id="username" name="username" required maxlength="%d" autocomplete="username"></label>`, accounts.MAX_USERNAME)
	fmt.sbprintf(b, `<label class="field"><span>Password</span><input id="password" name="password" type="password" required maxlength="%d" autocomplete="current-password"></label>`, accounts.MAX_PASSWORD)
	w(b, `<input type="hidden" name="next" value="`)
	esc(b, next)
	w(b, `"><button class="btn btn-primary" type="submit">Sign in</button><p class="field-msg form-error" id="login-error" role="alert"></p></form>`)
	if insecure {
		w(b, `<p class="muted login-insecure" role="note">This site runs with COOKIE_SECURE=0: the session cookie also travels over plain http.</p>`)
	}
	w(b, `</section>`)
}

// What a signed-in visitor sees at /login.
signed_in :: proc(b: ^strings.Builder) {
	w(b, `<section class="block"><p><a class="btn btn-outline" href="/accounts/sessions">Your sessions</a></p>`)
	w(b, `<form hx-post="/logout"><button class="btn btn-outline" type="submit">Sign out</button></form></section>`)
}

// The member's sessions, newest first, each with Revoke; `current` is this request's.
sessions :: proc(b: ^strings.Builder, list: []m.Session, current: string) {
	w(b, `<section class="block" id="sessions"><ul class="session-list">`)
	for s in list {
		this := s.token_hash == current
		w(b, `<li class="session card">`)
		fmt.sbprintf(b, `<span>Signed in %s, last seen %s</span>`, html.time_ago(s.created_at / 1000), html.time_ago(s.last_seen / 1000))
		if this { w(b, ` <strong class="badge">this device</strong>`) }
		w(b, `<form hx-post="/accounts/sessions/revoke" hx-target="#sessions" hx-swap="outerHTML"><input type="hidden" name="session" value="`)
		esc(b, s.token_hash)
		fmt.sbprintf(b, `"><button class="btn btn-outline" type="submit">%s</button></form></li>`, "Sign out here" if this else "Revoke")
	}
	w(b, `</ul></section>`)
}
