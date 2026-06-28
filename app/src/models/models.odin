package models

// ---- domain model -------------------------------------------------------
//
// One entity, Contact, is enough to exercise every CRUD path and every list
// control (search / sort / paginate). Enums stay small and closed so the view
// layer can map each value to a fixed label and colour without a lookup table
// per call site.

Role :: enum {
	Engineer,
	Designer,
	Manager,
	Sales,
	Support,
}

Status :: enum {
	Active,
	Invited,
	Disabled,
}

Contact :: struct {
	id:     int,
	name:   string,
	email:  string,
	role:   Role,
	status: Status,
	score:  int, // 0..100 engagement, drives a progress bar in the table
}

ROLE_NAMES :: [Role]string {
	.Engineer = "Engineer",
	.Designer = "Designer",
	.Manager  = "Manager",
	.Sales    = "Sales",
	.Support  = "Support",
}

STATUS_NAMES :: [Status]string {
	.Active   = "Active",
	.Invited  = "Invited",
	.Disabled = "Disabled",
}

// ---- events: interactions between two contacts --------------------------
//
// The second entity, related to the first. An event records that one contact did
// something involving another (both FKs into `contacts`, ON DELETE CASCADE), so
// deleting a contact removes the interactions it took part in. This is the real
// data behind the detail drawer's activity timeline.

Event_Kind :: enum {
	Introduced,
	Mentioned,
	Reviewed,
	Messaged,
}

EVENT_KIND_NAMES :: [Event_Kind]string {
	.Introduced = "Introduced",
	.Mentioned  = "Mentioned",
	.Reviewed   = "Reviewed",
	.Messaged   = "Messaged",
}

// A row in the events table: actor did `kind` involving target, at a unix time.
Event :: struct {
	id:        int,
	actor_id:  int,
	target_id: int,
	kind:      Event_Kind,
	at:        i64, // unix seconds
	note:      string,
}

// A contact-centric view of an event (the result of the timeline join): the OTHER
// party resolved to its id+name, and the direction relative to the contact whose
// timeline this is. `outgoing` = this contact was the actor.
Interaction :: struct {
	id:         int,
	kind:       Event_Kind,
	at:         i64,
	note:       string,
	other_id:   int,
	other_name: string,
	outgoing:   bool,
}

// Parse a label back to its enum value. Used when decoding form submissions;
// an unknown string falls back to the zero value so a hand-crafted POST can't
// crash a handler.
role_from :: proc(s: string) -> (Role, bool) {
	names := ROLE_NAMES
	for name, r in names {
		if name == s {
			return r, true
		}
	}
	return .Engineer, false
}

status_from :: proc(s: string) -> (Status, bool) {
	names := STATUS_NAMES
	for name, st in names {
		if name == s {
			return st, true
		}
	}
	return .Active, false
}
