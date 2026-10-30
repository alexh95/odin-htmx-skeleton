package authz

import "core:testing"

// §17.1's table as tabled, Q31's three judgement calls included: rbac.spec freezes it
// over every route at M4; this holds the table itself.
@(test)
role_perms_are_the_tabled_ones :: proc(t: ^testing.T) {
	for p in ([]Perm{.Bot_Use, .Video_Watch, .Wiki_Read}) {
		for r in Role { testing.expectf(t, p in ROLE_PERMS[r], "%v lacks %v", r, p) }
	}
	testing.expect(t, .Chat_Read not_in ROLE_PERMS[.Guest])
	testing.expect(t, .Chat_Read in ROLE_PERMS[.User])
	testing.expect(t, .Chat_Moderate not_in ROLE_PERMS[.User])
	// Q31: Term_Watch and Video_Upload from Moderator up, Admin_Audit for Admin alone.
	testing.expect(t, .Term_Watch not_in ROLE_PERMS[.User] && .Term_Watch in ROLE_PERMS[.Mod])
	testing.expect(t, .Video_Upload not_in ROLE_PERMS[.User] && .Video_Upload in ROLE_PERMS[.Mod])
	testing.expect(t, .Admin_Audit not_in ROLE_PERMS[.Mod] && .Admin_Audit in ROLE_PERMS[.Admin])
	testing.expect(t, .Term_Write not_in ROLE_PERMS[.Mod] && .Term_Write in ROLE_PERMS[.Admin])
	for r in Role {
		testing.expect(t, .Public not_in ROLE_PERMS[r]) // never granted: `can` answers it
		testing.expect(t, ROLE_PERMS[r] <= ROLE_PERMS[.Admin])
	}
}

@(test)
each_rule_has_its_answer :: proc(t: ^testing.T) {
	NOW :: i64(1_800_000_000)
	guest := GUEST
	member := Viewer{id = 1, role = .User}
	admin := Viewer{id = 2, role = .Admin, step_up_at = NOW - 60}
	stale := Viewer{id = 3, role = .Admin, step_up_at = NOW - STEP_UP_WINDOW - 1}

	testing.expect_value(t, refusal(guest, {perm = .Public}, false, NOW), Refusal.None)
	testing.expect_value(t, refusal(guest, {perm = .Chat_Read}, true, NOW), Refusal.Sign_In)
	testing.expect_value(t, refusal(member, {perm = .Chat_Read}, true, NOW), Refusal.None)
	testing.expect_value(t, refusal(member, {perm = .Admin_Ops}, true, NOW), Refusal.Forbidden)

	// Off the LAN a .Lan_Only row isn't there, whoever asks; on it, the perm decides.
	testing.expect_value(t, refusal(admin, {perm = .Admin_Ops, lan_only = true}, false, NOW), Refusal.Not_Found)
	testing.expect_value(t, refusal(guest, {perm = .Admin_Ops, lan_only = true}, false, NOW), Refusal.Not_Found)
	testing.expect_value(t, refusal(admin, {perm = .Admin_Ops, lan_only = true}, true, NOW), Refusal.None)

	// .Step_Up: within the window passes; stale, never, or a time ahead of now steps up; a
	// guest signs in first; the perm is checked before freshness.
	rule := Rule{perm = .Admin_Accounts, step_up = true}
	testing.expect_value(t, refusal(admin, rule, true, NOW), Refusal.None)
	testing.expect_value(t, refusal(stale, rule, true, NOW), Refusal.Step_Up)
	testing.expect_value(t, refusal(Viewer{id = 4, role = .Admin}, rule, true, NOW), Refusal.Step_Up)
	testing.expect_value(t, refusal(Viewer{id = 5, role = .Admin, step_up_at = NOW + 60}, rule, true, NOW), Refusal.Step_Up)
	testing.expect_value(t, refusal(guest, rule, true, NOW), Refusal.Sign_In)
	testing.expect_value(t, refusal(member, rule, true, NOW), Refusal.Forbidden)
	testing.expect_value(t, refusal(admin, {perm = .Admin_Accounts, step_up = true}, true, NOW + STEP_UP_WINDOW - 60), Refusal.None)
	testing.expect_value(t, refusal(admin, {perm = .Admin_Accounts, step_up = true}, true, NOW + STEP_UP_WINDOW - 59), Refusal.Step_Up)
}
