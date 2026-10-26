package contacts

// ---- contacts: the domain ------------------------------------------------------------------
//
// Search, sort, page, validate: plain values and errors, never HTTP. Every list
// control funnels through `page`, so the table fragment, the page and any other
// caller share one definition of "what the user is looking at"; the work itself
// (filter, sort, page, count) runs in SQL, and this decides what to ask.

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

import "../../platform/store"
import m "models"
import contacts_store "store:contacts"

// What other features' domains use (dashboard, gallery): they reach contacts
// through this package only (§5.1), never its models or its store.
Contact :: m.Contact
Role :: m.Role
Status :: m.Status
Error :: m.Error
Contact_Stats :: m.Contact_Stats
SCORE_BANDS :: m.SCORE_BANDS
Write :: m.Write
Write_Kind :: m.Write_Kind
role_from :: m.role_from
status_from :: m.status_from

// The labels, in enum order, for a form's options.
role_labels :: proc() -> []string { return slice.enumerated_array(&m.ROLE_NAMES) }

PAGE_SIZE :: 7
SEARCH_LIMIT :: 6 // the nav search dropdown's rows
API_LIMIT :: 100 // what /api/search returns at most; a client narrows q for more

// Field limits, in characters: roomy for real data, small enough that one
// request can't park megabytes in the store and in every page that renders it.
// The inputs carry the same numbers as maxlength, so the browser stops first.
MAX_NAME :: 100
MAX_EMAIL :: 254 // the longest address SMTP can carry (RFC 5321)
MAX_NOTES :: 1000

Page :: struct {
	rows:        []m.Contact,
	page:        int,
	total_pages: int,
	total:       int,
	q:           string,
	status:      string, // the quick filter: "" or "all" for none, else a status label
	sort:        string,
}

Field_Error :: struct {
	field: string,
	msg:   string,
}

// q against the name and email (in SQL) and the role and status labels, which
// are fixed, so worked out here as bitmasks; plus the quick filter's status.
filter :: proc(q, status: string) -> m.Filter {
	f := m.Filter{q = strings.trim_space(q), status = -1}
	if f.q != "" {
		for name, r in m.ROLE_NAMES {
			if store.contains_ci(name, f.q) { f.role_mask |= 1 << u32(r) }
		}
		for name, s in m.STATUS_NAMES {
			if store.contains_ci(name, f.q) { f.status_mask |= 1 << u32(s) }
		}
	}
	if st, ok := m.status_from(status); ok { f.status = int(st) }
	return f
}

// One page of the filtered list, sorted by a "key" or "key_desc" string, clamped
// to the pages there are.
page :: proc(q, status, sort: string, page: int) -> (p: Page, err: m.Error) {
	f := filter(q, status)
	key, desc := parse_sort(sort)
	p.total = contacts_store.filter_count(f) or_return
	p.total_pages = max(1, (p.total + PAGE_SIZE - 1) / PAGE_SIZE)
	p.page = clamp(page, 1, p.total_pages)
	rows := make([dynamic]m.Contact, context.temp_allocator)
	contacts_store.page(f, key, desc, PAGE_SIZE, (p.page - 1) * PAGE_SIZE, &rows) or_return
	p.rows = rows[:]
	p.q, p.status, p.sort = q, status, sort
	return
}

// "score_desc" → (.Score, true). Anything unrecognised sorts by name.
parse_sort :: proc(sort: string) -> (key: m.Sort, desc: bool) {
	name := sort
	if strings.has_suffix(sort, "_desc") {
		desc = true
		name = sort[:len(sort) - len("_desc")]
	}
	switch name {
	case "email":  key = .Email
	case "role":   key = .Role
	case "status": key = .Status
	case "score":  key = .Score
	case:          key = .Name
	}
	return
}

// A column header's next sort: first click ascending, second descending.
next_sort :: proc(current, column: string) -> string {
	if current == column { return strings.concatenate({column, "_desc"}, context.temp_allocator) }
	return column
}

// The JSON API's matches, at most API_LIMIT, in id order; an empty query lists
// the first API_LIMIT.
search_all :: proc(q: string) -> ([]m.Contact, m.Error) {
	out := make([dynamic]m.Contact, context.temp_allocator)
	err := contacts_store.match(filter(q, ""), API_LIMIT, &out)
	return out[:], err
}

// The dropdown's first `limit` matches; nothing for an empty query.
search :: proc(q: string, limit: int) -> ([]m.Contact, m.Error) {
	if strings.trim_space(q) == "" { return {}, .None }
	out := make([dynamic]m.Contact, context.temp_allocator)
	err := contacts_store.match(filter(q, ""), limit, &out)
	return out[:], err
}

get :: proc(id: i64) -> (m.Contact, m.Error) {
	return contacts_store.get(id)
}

stats :: proc() -> (m.Contact_Stats, m.Error) {
	return contacts_store.stats()
}

// Everything the detail drawer shows: the contact, its timeline (real
// interactions with other contacts), and others sharing its role.
Detail :: struct {
	contact:  m.Contact,
	timeline: []m.Interaction,
	related:  []m.Contact,
}

detail :: proc(id: i64) -> (d: Detail, err: m.Error) {
	d.contact = contacts_store.get(id) or_return
	tl := make([dynamic]m.Interaction, context.temp_allocator)
	contacts_store.timeline(id, &tl) or_return
	rel := make([dynamic]m.Contact, context.temp_allocator)
	contacts_store.related(id, d.contact.role, 4, &rel) or_return
	d.timeline, d.related = tl[:], rel[:]
	return
}

// A relative time for the timeline, in days.
time_ago :: proc(at: i64) -> string {
	d := int((time.time_to_unix(time.now()) - at) / 86400)
	switch {
	case d <= 0:  return "today"
	case d == 1:  return "yesterday"
	case d < 14:  return fmt.tprintf("%d days ago", d)
	case d < 60:  return fmt.tprintf("%d weeks ago", d / 7)
	}
	return fmt.tprintf("%d months ago", d / 30)
}

// ---- writes ---------------------------------------------------------------------------------
//
// The caller builds a Write op (store.new_op), sets its done, and hands it here;
// done runs on the caller's loop once the write is committed. Validation runs
// first, synchronously: a refused contact never reaches the store.

// The trimmed, validated contact for a create, or why not (the user's to fix).
check_create :: proc(name, email: string, role: m.Role, status: m.Status, score: int, notes := "", notify := false) -> (c: m.Contact, errs: []Field_Error) {
	if errs = validate(name, email, notes); len(errs) > 0 { return }
	return m.Contact{
		name = strings.trim_space(name), email = strings.trim_space(email), role = role, status = status,
		score = clamp(score, 0, 100), notes = strings.trim_space(notes), notify = notify,
	}, nil
}

// The drawer's full edit: the trimmed fields, or why not.
check_update :: proc(name, email: string, role: m.Role, status: m.Status, score: int) -> (c: m.Contact, errs: []Field_Error) {
	if errs = validate(name, email); len(errs) > 0 { return }
	return m.Contact{name = strings.trim_space(name), email = strings.trim_space(email), role = role, status = status, score = clamp(score, 0, 100)}, nil
}

// Queues the op (create, update, cycle or delete). false: the store is busy.
write :: proc(w: ^m.Write) -> bool {
	return contacts_store.write(w)
}

// The demo rows, into empty tables only.
seed :: proc() {
	contacts_store.seed()
}

// ---- validation -----------------------------------------------------------------------------

valid_email :: proc(s: string) -> bool {
	at := strings.index_byte(s, '@')
	if at <= 0 { return false }
	dot := strings.last_index_byte(s, '.')
	return dot > at + 1 && dot < len(s) - 1
}

validate :: proc(name, email: string, notes := "") -> []Field_Error {
	errs := make([dynamic]Field_Error, context.temp_allocator)
	switch n := strings.trim_space(name); {
	case n == "":
		append(&errs, Field_Error{"name", "Name is required."})
	case utf8.rune_count_in_string(n) > MAX_NAME:
		append(&errs, Field_Error{"name", fmt.tprintf("Name must be at most %d characters.", MAX_NAME)})
	}
	switch e := strings.trim_space(email); {
	case utf8.rune_count_in_string(e) > MAX_EMAIL:
		append(&errs, Field_Error{"email", fmt.tprintf("Email must be at most %d characters.", MAX_EMAIL)})
	case !valid_email(e):
		append(&errs, Field_Error{"email", "Enter a valid email address."})
	}
	if utf8.rune_count_in_string(strings.trim_space(notes)) > MAX_NOTES {
		append(&errs, Field_Error{"notes", fmt.tprintf("Notes must be at most %d characters.", MAX_NOTES)})
	}
	return errs[:]
}

// How many bytes a Write op needs for its strings: its input, and the row read
// back, whose fields are capped in characters of up to 4 bytes.
op_bytes :: proc(c: m.Contact) -> int {
	return len(c.name) + len(c.email) + len(c.notes) + 4 * (MAX_NAME + MAX_EMAIL + MAX_NOTES)
}
