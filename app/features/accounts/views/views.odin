package accounts_views

// ---- accounts' views: sign-in, the code step, step-up, two-step setup and sessions ----------

import "core:fmt"
import "core:strings"

import "../../../platform/html"
import accounts ".."
import m "../models"

w :: html.w
esc :: html.esc

// The sign-in form. A refusal (422 wrong, 429 backed off or too many, 503 busy) lands in its
// error slot and leaves both fields as typed; an account with two-step sign-in gets the code
// form in its place (a 200, swapped over the form).
login_form :: proc(b: ^strings.Builder, next: string, insecure: bool) {
	w(b, `<section class="block"><form class="card login-form" hx-post="/login" hx-target="this" hx-swap="outerHTML"
      hx-status:4xx="target:#login-error swap:innerHTML" hx-status:5xx="target:#login-error swap:innerHTML">`)
	fmt.sbprintf(b, `<label class="field"><span>Username</span><input id="username" name="username" required maxlength="%d" autocomplete="username"></label>`, accounts.MAX_USERNAME)
	fmt.sbprintf(b, `<label class="field"><span>Password</span><input id="password" name="password" type="password" required maxlength="%d" autocomplete="current-password"></label>`, accounts.MAX_PASSWORD)
	hidden(b, "next", next)
	w(b, `<button class="btn btn-primary" type="submit">Sign in</button><p class="field-msg form-error" id="login-error" role="alert"></p></form>`)
	if insecure {
		w(b, `<p class="muted login-insecure" role="note">This site runs with COOKIE_SECURE=0: the session cookie also travels over plain http.</p>`)
	}
	w(b, `</section>`)
}

// The sign-in's second step: a code from the app, or one of the recovery codes.
code_form :: proc(b: ^strings.Builder, pending, next: string) {
	w(b, `<form class="card login-form code-form" hx-post="/login/code"
      hx-status:4xx="target:#login-error swap:innerHTML" hx-status:5xx="target:#login-error swap:innerHTML">`)
	w(b, `<label class="field"><span>Code from your app, or a recovery code</span><input id="code" name="code" required maxlength="16" autocomplete="one-time-code" inputmode="text" autofocus></label>`)
	hidden(b, "pending", pending)
	hidden(b, "next", next)
	w(b, `<button class="btn btn-primary" type="submit">Continue</button><p class="field-msg form-error" id="login-error" role="alert"></p></form>`)
}

// /step-up's form: the password, or (with two-step sign-in) a code.
step_up_form :: proc(b: ^strings.Builder, next: string, has_totp: bool) {
	w(b, `<section class="block"><form class="card login-form" hx-post="/step-up"
      hx-status:4xx="target:#step-up-error swap:innerHTML" hx-status:5xx="target:#step-up-error swap:innerHTML">`)
	fmt.sbprintf(b, `<label class="field"><span>%s</span><input id="secret" name="secret" type="password" required maxlength="%d" autocomplete="current-password"></label>`,
		"Password, or a code from your app" if has_totp else "Password", accounts.MAX_PASSWORD)
	hidden(b, "next", next)
	w(b, `<button class="btn btn-primary" type="submit">Confirm</button><p class="field-msg form-error" id="step-up-error" role="alert"></p></form></section>`)
}

// Two-step sign-in off: the secret to type into an app, and the form that confirms it took.
totp_setup :: proc(b: ^strings.Builder, secret, uri: string, admin_needs_it: bool) {
	w(b, `<section class="block" id="totp">`)
	if admin_needs_it {
		w(b, `<p class="card totp-required" role="note">Admin pages open once two-step sign-in is on: until then this account is a Member.</p>`)
	}
	w(b, `<div class="card"><p>Add an account to your authenticator app with this key (time-based, six digits):</p><p><code class="totp-secret">`)
	esc(b, secret)
	w(b, `</code></p><p class="muted">Or paste this into an app that takes a link:</p><p><code class="totp-uri">`)
	esc(b, uri)
	w(b, `</code></p></div><form class="card totp-form" hx-post="/accounts/totp" hx-target="#totp" hx-swap="innerHTML"
      hx-status:4xx="target:#totp-error swap:innerHTML" hx-status:5xx="target:#totp-error swap:innerHTML">`)
	hidden(b, "secret", secret)
	w(b, `<label class="field"><span>The code the app shows now</span><input id="totp-code" name="code" required maxlength="8" inputmode="numeric" autocomplete="one-time-code"></label>`)
	w(b, `<button class="btn btn-primary" type="submit">Turn on</button><p class="field-msg form-error" id="totp-error" role="alert"></p></form></section>`)
}

// Two-step sign-in on: how many recovery codes are left, new ones, and off (both ask for a step-up).
totp_on :: proc(b: ^strings.Builder, recovery_left: int) {
	w(b, `<section class="block" id="totp"><div class="card">`)
	fmt.sbprintf(b, `<p class="totp-state">Two-step sign-in is on. %d of %d recovery codes left.</p>`, recovery_left, m.RECOVERY_CODES)
	w(b, `<form hx-post="/accounts/totp/codes" hx-target="#totp" hx-swap="innerHTML"><button class="btn btn-outline" type="submit">New recovery codes</button></form>`)
	w(b, `<form hx-post="/accounts/totp/off"><button class="btn btn-outline" type="submit">Turn off</button></form></div></section>`)
}

// The recovery codes, this once: each signs in once in place of the app's code.
recovery_codes :: proc(b: ^strings.Builder, codes: []string) {
	w(b, `<div class="card"><p class="totp-state">Two-step sign-in is on. Keep these recovery codes somewhere safe: each works once, in place of a code from the app, and they are not shown again.</p><ul class="recovery-codes">`)
	for c in codes {
		w(b, `<li><code>`)
		esc(b, c)
		w(b, `</code></li>`)
	}
	w(b, `</ul><p><a class="btn btn-outline" href="/accounts/totp">Done</a></p></div>`)
}

// What a signed-in visitor sees at /login.
signed_in :: proc(b: ^strings.Builder) {
	w(b, `<section class="block"><p><a class="btn btn-outline" href="/accounts/sessions">Your sessions</a> <a class="btn btn-outline" href="/accounts/totp">Two-step sign-in</a></p>`)
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

@(private)
hidden :: proc(b: ^strings.Builder, name, value: string) {
	fmt.sbprintf(b, `<input type="hidden" name="%s" value="`, name)
	esc(b, value)
	w(b, `">`)
}
