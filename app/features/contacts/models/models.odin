package contacts_models

// ---- contacts: the types and the store contract ----------------------------------------
//
// The skeleton's worked example: one entity, Contact, enough to exercise every
// CRUD path and every list control (filter, sort, page), and Event, the
// interactions between two contacts behind the detail drawer's timeline. Enums
// stay small and closed so a view maps each value to a fixed label and colour.

import "../../../platform/store"

Role :: enum u8 {
	Engineer,
	Designer,
	Manager,
	Sales,
	Support,
}

Status :: enum u8 {
	Active,
	Invited,
	Disabled,
}

Contact :: struct {
	id:     i64,
	name:   string,
	email:  string,
	role:   Role,
	status: Status,
	score:  int, // 0..100 engagement, a progress bar in the table
	notes:  string, // optional; "" when none
	notify: bool, // wants email about account activity
}

ROLE_NAMES := [Role]string {
	.Engineer = "Engineer",
	.Designer = "Designer",
	.Manager  = "Manager",
	.Sales    = "Sales",
	.Support  = "Support",
}

STATUS_NAMES := [Status]string {
	.Active   = "Active",
	.Invited  = "Invited",
	.Disabled = "Disabled",
}

// ---- events: interactions between two contacts ------------------------------------------
//
// An event records that one contact did something involving another (both FKs
// into contacts, ON DELETE CASCADE): deleting a contact removes the interactions
// it took part in.

Event_Kind :: enum u8 {
	Introduced,
	Mentioned,
	Reviewed,
	Messaged,
}

EVENT_KIND_NAMES := [Event_Kind]string {
	.Introduced = "Introduced",
	.Mentioned  = "Mentioned",
	.Reviewed   = "Reviewed",
	.Messaged   = "Messaged",
}

// One event from one contact's side (the timeline's join): the OTHER party
// resolved to its id and name, and whether this contact was the actor.
Interaction :: struct {
	id:         i64,
	kind:       Event_Kind,
	at:         i64,
	note:       string,
	other_id:   i64,
	other_name: string,
	outgoing:   bool,
}

// ---- the dashboard's aggregate -----------------------------------------------------------
//
// Counted by SQLite in one GROUP BY rather than by loading every contact;
// by_score splits the 0..100 score into SCORE_BANDS equal bands, lowest first.

SCORE_BANDS :: 8

Contact_Stats :: struct {
	by_status: [Status]int,
	by_role:   [Role]int,
	by_score:  [Status][SCORE_BANDS]int,
	score_sum: int,
}

// ---- what a list asks the store for --------------------------------------------------------

// q against the name and the email (in SQL), and against the role and status
// labels, which are fixed, so worked out as bitmasks; plus a status, or -1.
Filter :: struct {
	q:           string,
	role_mask:   u32, // bit r set: role r's label matches q
	status_mask: u32, // bit s set: status s's label matches q
	status:      int, // only this status; -1 for any
}

Sort :: enum u8 {
	Name,
	Email,
	Role,   // by label, A→Z, as the column shows it
	Status, // by label, A→Z
	Score,
}

// ---- the store contract (SQLite only: contacts' value is persistence, D18) -------------------

Error :: store.Error

// One write: create, update, cycle or delete. The caller's `done` runs once it is
// committed, with `result` the row as stored (its strings in the op's own memory).
Write_Kind :: enum u8 {
	Create,
	Update,
	Cycle,
	Delete,
}

Write :: struct {
	using op: store.Op,
	kind:     Write_Kind,
	id:       i64, // update, cycle, delete
	input:    Contact, // create, update: trimmed and validated by the domain
	result:   Contact,
}

Store_Page :: proc(f: Filter, key: Sort, desc: bool, limit, offset: int, out: ^[dynamic]Contact) -> Error
Store_Filter_Count :: proc(f: Filter) -> (int, Error)
Store_Match :: proc(f: Filter, limit: int, out: ^[dynamic]Contact) -> Error
Store_Related :: proc(id: i64, role: Role, limit: int, out: ^[dynamic]Contact) -> Error
Store_Get :: proc(id: i64) -> (Contact, Error)
Store_Stats :: proc() -> (Contact_Stats, Error)
Store_Timeline :: proc(id: i64, out: ^[dynamic]Interaction) -> Error
Store_Write :: proc(w: ^Write) -> bool // false: the writer is busy; `done` won't run
Store_Seed :: proc()
// Every contact and event gone and the demo rows back, in one transaction: a demo's nightly reset.
Store_Reset :: proc() -> bool

// A label back to its value (forms send labels); false for anything else.
role_from :: proc(s: string) -> (Role, bool) {
	for name, r in ROLE_NAMES {
		if name == s { return r, true }
	}
	return .Engineer, false
}

status_from :: proc(s: string) -> (Status, bool) {
	for name, st in STATUS_NAMES {
		if name == s { return st, true }
	}
	return .Active, false
}
