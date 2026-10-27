package authz

// ---- platform/authz: who may do what (L2) ----------------------------------
//
// D35, PLAN §17.1. One closed Perm enum, grouped by feature, one ROLE_PERMS
// table, no per-user grants. A route row names the perm it needs (`.Public` for
// none) and `front` checks it before a byte of the body is read; services check
// per item (own message, room moderator). The build's identity, a member of the
// `identity:` family, loads the Viewer through the contract below.

import "core:net"
import "core:strings"

Role :: enum u8 {
	Guest,
	User,
	Mod,
	Admin,
}

ROLE_LABELS := [Role]string {
	.Guest = "Guest",
	.User  = "Member",
	.Mod   = "Moderator",
	.Admin = "Admin",
}

Perm :: enum u8 {
	Public, // no check (D5); never granted, never required
	Account_Self,
	Chat_Read, Chat_Post, Chat_Dm, Chat_Create_Room, Chat_Attach, Chat_Moderate,
	Bot_Use, Bot_Llama,
	Video_Watch, Video_Upload, Video_Moderate,
	Wiki_Read, Wiki_Edit,
	Lists_Edit,
	Polls_Create, Polls_Vote,
	Calendar_Edit,
	Guestbook_Moderate,
	C4_Play,
	Term_Watch, Term_Write,
	Admin_Accounts, Admin_Audit, Admin_Ops, Admin_Jobs, Admin_Modules, Admin_Db, Admin_Term,
}

Perms :: bit_set[Perm; u64]

@(private = "file")
EVERYONE :: Perms{.Bot_Use, .Video_Watch, .Wiki_Read}
@(private = "file")
MEMBERS :: EVERYONE + Perms{
	.Account_Self, .Chat_Read, .Chat_Post, .Chat_Dm, .Chat_Create_Room, .Chat_Attach, .Bot_Llama,
	.Wiki_Edit, .Lists_Edit, .Polls_Create, .Polls_Vote, .Calendar_Edit, .C4_Play,
}
@(private = "file")
MODS :: MEMBERS + Perms{.Chat_Moderate, .Video_Upload, .Video_Moderate, .Guestbook_Moderate, .Term_Watch}

// The plan's default table; Term_Watch, Video_Upload and Admin_Audit are Q31's
// judgement calls, and rbac.spec freezes the whole table at M4.
ROLE_PERMS := [Role]Perms {
	.Guest = EVERYONE,
	.User  = MEMBERS,
	.Mod   = MODS,
	.Admin = MODS + Perms{.Term_Write, .Admin_Accounts, .Admin_Audit, .Admin_Ops, .Admin_Jobs, .Admin_Modules, .Admin_Db, .Admin_Term},
}

// Who is asking, as the build's identity loaded them. Views get it only to hide
// controls; enforcement is front's and the services'.
Viewer :: struct {
	id:   u64, // 0 = no account
	name: string,
	role: Role,
}

GUEST :: Viewer{role = .Guest}

can :: proc(v: Viewer, p: Perm) -> bool {
	return p == .Public || p in ROLE_PERMS[v.role]
}

// What front hands the identity, before the body is read: only platform/web
// touches odin-http's types, so the contract carries the parts an identity reads.
Ask :: struct {
	cookies: string,      // the Cookie header, as sent
	client:  net.Address, // the trusted client address (§17.8)
	https:   bool,        // arrived as https through a trusted proxy (COOKIE_SECURE=auto)
}

// One cookie's value from a Cookie header ("" when absent): an identity's, and
// web.cookie's for a handler.
cookie :: proc(header, name: string) -> string {
	rest := header
	for part in strings.split_iterator(&rest, ";") {
		k, _, v := strings.partition(strings.trim_space(part), "=")
		if k == name { return v }
	}
	return ""
}

// The identity contract: each member of the `identity:` family declares
// `_ : authz.Load_Viewer : load_viewer` in its contract.odin. `set_cookie` is a
// Set-Cookie value for front to send (a rotated session), or "".
Load_Viewer :: #type proc(ask: Ask) -> (v: Viewer, set_cookie: string)
