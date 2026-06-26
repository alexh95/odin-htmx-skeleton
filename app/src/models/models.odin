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
