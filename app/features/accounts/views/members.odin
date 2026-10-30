package accounts_views

// ---- joining, resetting, the profile, and /admin/accounts -----------------------------------

import "core:fmt"
import "core:strings"

import accounts ".."
import m "../models"

// A form whose refusals land in its own error slot, keeping every field as typed.
@(private)
form_open :: proc(b: ^strings.Builder, action, class, slot: string) {
	fmt.sbprintf(b, `<section class="block"><form class="card %s" hx-post="%s"
      hx-status:4xx="target:#%s swap:innerHTML" hx-status:5xx="target:#%s swap:innerHTML">`, class, action, slot, slot)
}

@(private)
form_close :: proc(b: ^strings.Builder, button, slot: string) {
	fmt.sbprintf(b, `<button class="btn btn-primary" type="submit">%s</button><p class="field-msg form-error" id="%s" role="alert"></p></form></section>`, button, slot)
}

@(private)
new_password_fields :: proc(b: ^strings.Builder) {
	fmt.sbprintf(b, `<label class="field"><span>Password</span><input id="password" name="password" type="password" required minlength="10" maxlength="%d" autocomplete="new-password"></label>`, accounts.MAX_PASSWORD)
	fmt.sbprintf(b, `<label class="field"><span>The same again</span><input id="again" name="again" type="password" required minlength="10" maxlength="%d" autocomplete="new-password"></label>`, accounts.MAX_PASSWORD)
}

// /register's form; `code` prefilled from the invite link.
register_form :: proc(b: ^strings.Builder, code: string, needs_code: bool) {
	form_open(b, "/register", "register-form", "register-error")
	fmt.sbprintf(b, `<label class="field"><span>Username</span><input id="username" name="username" required minlength="%d" maxlength="%d" autocomplete="username"></label>`, accounts.MIN_USERNAME, accounts.MAX_USERNAME_NEW)
	fmt.sbprintf(b, `<label class="field"><span>Name to show</span><input id="display" name="display" maxlength="%d" autocomplete="nickname" placeholder="your username"></label>`, accounts.MAX_DISPLAY)
	new_password_fields(b)
	fmt.sbprintf(b, `<label class="field"><span>Invite code%s</span><input id="code" name="code" maxlength="40" value="`, "" if needs_code else " (if you have one)")
	esc(b, code)
	w(b, `"`)
	if needs_code { w(b, ` required`) }
	w(b, `></label>`)
	form_close(b, "Join", "register-error")
}

reset_form :: proc(b: ^strings.Builder) {
	form_open(b, "/reset", "reset-form", "reset-error")
	fmt.sbprintf(b, `<label class="field"><span>Username</span><input id="username" name="username" required maxlength="%d" autocomplete="username"></label>`, accounts.MAX_USERNAME)
	w(b, `<label class="field"><span>Reset code</span><input id="code" name="code" required maxlength="20" autocomplete="off"></label>`)
	new_password_fields(b)
	form_close(b, "Set the new password", "reset-error")
}

// A save answers "Saved." into the same slot a refusal goes to.
profile_form :: proc(b: ^strings.Builder, display: string) {
	w(b, `<section class="block"><form class="card profile-form" hx-post="/accounts/profile" hx-target="#profile-msg" hx-swap="innerHTML">`)
	fmt.sbprintf(b, `<label class="field"><span>Name to show</span><input id="display" name="display" required maxlength="%d" value="`, accounts.MAX_DISPLAY)
	esc(b, display)
	w(b, `"></label>`)
	form_close(b, "Save", "profile-msg")
}

// ---- /admin/accounts ------------------------------------------------------------------------

// Every write asks for a reason (hx-prompt); refusals arrive as toasts.
admin_accounts :: proc(b: ^strings.Builder, users: []m.User, invites: []m.Invite, me: i64) {
	w(b, `<section class="block"><div id="admin-result" aria-live="polite"></div><table class="table admin-users"><thead><tr><th>Username</th><th>Name</th><th>Role</th><th>Status</th><th>Two-step</th><th>Change</th></tr></thead><tbody>`)
	for u in users {
		fmt.sbprintf(b, `<tr class="admin-user" id="user-%d"><td>`, u.id)
		esc(b, u.username)
		w(b, `</td><td>`)
		esc(b, u.display)
		fmt.sbprintf(b, `</td><td>%s</td><td>%s</td><td>%s</td><td class="admin-actions">`, m.role_label(u.role), "disabled" if u.disabled_at != 0 else "active", "on" if u.totp_secret != "" else "off")
		fmt.sbprintf(b, `<form class="admin-role" hx-post="/admin/accounts/%d/role" hx-prompt="Why change this role?" hx-swap="none"><select name="role" aria-label="Role">`, u.id)
		for r in m.Role {
		label := m.role_label(r)
			if r == .Guest { continue }
			fmt.sbprintf(b, `<option%s>%s</option>`, " selected" if r == u.role else "", label)
		}
		w(b, `</select><button class="btn btn-outline" type="submit">Set role</button></form>`)
		if u.disabled_at != 0 {
			fmt.sbprintf(b, `<button class="btn btn-outline" hx-post="/admin/accounts/%d/enable" hx-prompt="Why enable this account?" hx-swap="none">Enable</button>`, u.id)
		} else if u.id != me {
			fmt.sbprintf(b, `<button class="btn btn-outline" hx-post="/admin/accounts/%d/disable" hx-prompt="Why disable this account?" hx-swap="none">Disable</button>`, u.id)
		}
		fmt.sbprintf(b, `<button class="btn btn-outline" hx-post="/admin/accounts/%d/reset" hx-prompt="Why a reset code?" hx-target="#admin-result" hx-swap="innerHTML">Reset code</button>`, u.id)
		if u.totp_secret != "" {
			fmt.sbprintf(b, `<button class="btn btn-outline" hx-post="/admin/accounts/%d/two-step-off" hx-prompt="Why turn their two-step sign-in off?" hx-swap="none">Two-step off</button>`, u.id)
		}
		w(b, `</td></tr>`)
	}
	w(b, `</tbody></table></section>`)

	w(b, `<section class="block"><h2>Invites</h2><form class="card admin-invite" hx-post="/admin/accounts/invites" hx-prompt="Who is this invite for?" hx-target="#admin-result" hx-swap="innerHTML"><label class="field"><span>Role</span><select name="role">`)
	for r in m.Role {
		label := m.role_label(r)
		if r == .Guest { continue }
		fmt.sbprintf(b, `<option%s>%s</option>`, " selected" if r == .User else "", label)
	}
	w(b, `</select></label><label class="field"><span>Uses</span><input name="uses" type="number" min="1" max="50" value="1"></label><label class="field"><span>Days</span><input name="days" type="number" min="1" max="30" value="7"></label><button class="btn btn-primary" type="submit">Make an invite</button></form>`)
	w(b, `<ul class="admin-invites">`)
	for inv in invites {
		fmt.sbprintf(b, `<li class="admin-invite-row">%s, %d of %d used, until %s <form hx-post="/admin/accounts/invites/delete" hx-prompt="Why withdraw this invite?" hx-swap="none"><input type="hidden" name="invite" value="`, m.role_label(inv.role), inv.uses, inv.max_uses, day(inv.expires_at))
		esc(b, inv.code_hash)
		w(b, `"><button class="btn btn-outline" type="submit">Withdraw</button></form></li>`)
	}
	w(b, `</ul></section>`)
}

@(private)
day :: proc(ms: i64) -> string {
	days := ms / 86_400_000
	// Civil date from days since 1970 (Howard Hinnant's algorithm).
	z := days + 719468
	era := z / 146097
	doe := z - era * 146097
	yoe := (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	y := yoe + era * 400
	doy := doe - (365 * yoe + yoe / 4 - yoe / 100)
	mp := (5 * doy + 2) / 153
	d := doy - (153 * mp + 2) / 5 + 1
	mo := mp + 3 if mp < 10 else mp - 9
	if mo <= 2 { y += 1 }
	return fmt.tprintf("%04d-%02d-%02d", y, mo, d)
}

// A new reset code, this once: the admin reads it out to the member.
reset_issued :: proc(b: ^strings.Builder, username, code: string) {
	w(b, `<div class="card admin-shown"><p>A one-time reset code for <strong>`)
	esc(b, username)
	w(b, `</strong>, for 24 hours: <code class="reset-code">`)
	esc(b, code)
	w(b, `</code>. They enter it at <a href="/reset">/reset</a> with a new password. It is not shown again.</p></div>`)
}

// A new invite link, this once.
invite_made :: proc(b: ^strings.Builder, link, role: string, uses, days: int) {
	fmt.sbprintf(b, `<div class="card admin-shown"><p>An invite for %d %s, for %d days: <code class="invite-link">`, uses, "member" if uses == 1 else "members", days)
	esc(b, link)
	fmt.sbprintf(b, `</code> (as %s). It is not shown again.</p></div>`, role)
}
