package services
import "../repository"
import "../models"

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

// ---- services -----------------------------------------------------------
//
// Business logic over the repository: search, sort, paginate, validate. This
// layer returns plain values and never touches http. The list controls all
// funnel through service_page so the table fragment, the page, and any future
// caller share one definition of "what the user is looking at".

PAGE_SIZE :: 7
SEARCH_LIMIT :: 6 // results shown in the nav search dropdown

// A store failure, passed up as a value for the controller to answer (404, 409
// or 500). Re-exported so the controllers need not import the repository.
Store_Error :: repository.Error

// Whether the store answers; /healthz reports it.
store_ok :: proc() -> bool {
	return repository.repo_ping()
}

Page :: struct {
	rows:        []models.Contact,
	page:        int,
	total_pages: int,
	total:       int,
	q:           string,
	status:      string, // active quick-filter ("" / "all" = no filter, else a status name)
	sort:        string,
}

// Case-insensitive substring test. Lower-cases both sides into the request
// arena; cheap, and the arena is wiped after the response is sent.
contains_ci :: proc(haystack, needle: string) -> bool {
	if needle == "" {
		return true
	}
	h := strings.to_lower(haystack, context.temp_allocator)
	n := strings.to_lower(needle, context.temp_allocator)
	return strings.contains(h, n)
}

contact_matches :: proc(c: models.Contact, q: string) -> bool {
	if q == "" {
		return true
	}
	role := models.ROLE_NAMES
	status := models.STATUS_NAMES
	return(
		contains_ci(c.name, q) ||
		contains_ci(c.email, q) ||
		contains_ci(role[c.role], q) ||
		contains_ci(status[c.status], q) \
	)
}

// A list view: filter by q, sort by a "key" or "key_desc" string, then slice
// out one page. Everything is built in the request arena.
service_page :: proc(q, status, sort: string, page: int) -> (Page, Store_Error) {
	sn := models.STATUS_NAMES
	all, err := repository.repo_list()
	if err != .None {
		return {}, err
	}
	filtered := make([dynamic]models.Contact, context.temp_allocator)
	for c in all {
		if !contact_matches(c, q) {
			continue
		}
		if status != "" && status != "all" && sn[c.status] != status {
			continue
		}
		append(&filtered, c)
	}

	sort_contacts(filtered[:], sort)

	total := len(filtered)
	total_pages := max(1, (total + PAGE_SIZE - 1) / PAGE_SIZE)
	p := clamp(page, 1, total_pages)

	start := min((p - 1) * PAGE_SIZE, total)
	end := min(start + PAGE_SIZE, total)

	return Page {
		rows = filtered[start:end],
		page = p,
		total_pages = total_pages,
		total = total,
		q = q,
		status = status,
		sort = sort,
	}, .None
}

// Sort ascending by the chosen key, then reverse for "_desc". Reversing after
// the fact keeps one comparator per key instead of one per (key, direction).
sort_contacts :: proc(rows: []models.Contact, sort: string) {
	key := sort
	desc := false
	if strings.has_suffix(sort, "_desc") {
		desc = true
		key = sort[:len(sort) - len("_desc")]
	}

	switch key {
	case "email":
		slice.sort_by(rows, proc(a, b: models.Contact) -> bool { return a.email < b.email })
	case "role":
		slice.sort_by(rows, proc(a, b: models.Contact) -> bool {
			names := models.ROLE_NAMES
			return names[a.role] < names[b.role]
		})
	case "status":
		slice.sort_by(rows, proc(a, b: models.Contact) -> bool {
			names := models.STATUS_NAMES
			return names[a.status] < names[b.status]
		})
	case "score":
		slice.sort_by(rows, proc(a, b: models.Contact) -> bool { return a.score < b.score })
	case: // "name" and anything unrecognised
		slice.sort_by(rows, proc(a, b: models.Contact) -> bool { return a.name < b.name })
	}

	if desc {
		slice.reverse(rows)
	}
}

// Flip a sort key for a column header click: first click ascending, second
// descending, anything else resets to this column ascending.
next_sort :: proc(current, column: string) -> string {
	if current == column {
		return strings.concatenate({column, "_desc"}, context.temp_allocator)
	}
	return column
}

// Every match for the JSON API; an empty query lists everyone.
search_all :: proc(q: string) -> ([]models.Contact, Store_Error) {
	all, err := repository.repo_list()
	out := make([dynamic]models.Contact, context.temp_allocator)
	for c in all {
		if contact_matches(c, q) {
			append(&out, c)
		}
	}
	return out[:], err
}

service_search :: proc(q: string, limit: int) -> ([]models.Contact, Store_Error) {
	out := make([dynamic]models.Contact, context.temp_allocator)
	if strings.trim_space(q) == "" {
		return out[:], .None
	}
	all, err := repository.repo_list()
	for c in all {
		if contact_matches(c, q) {
			append(&out, c)
			if len(out) >= limit {
				break
			}
		}
	}
	return out[:], err
}

// ---- detail view: interaction timeline + related ------------------------
//
// The contact detail drills past the table row. The activity feed is now real:
// the contact's `events` timeline — interactions with other contacts, joined to
// resolve the other party (see repository/events.odin). Related = others sharing
// the role, a second, simpler relationship.

service_timeline :: proc(c: models.Contact) -> ([]models.Interaction, Store_Error) {
	return repository.event_timeline(c.id)
}

// Relative-time label from a unix timestamp, for the timeline.
time_ago :: proc(at: i64) -> string {
	d := int((time.time_to_unix(time.now()) - at) / 86400)
	switch {
	case d <= 0:
		return "today"
	case d == 1:
		return "yesterday"
	case d < 14:
		return fmt.tprintf("%d days ago", d)
	case d < 60:
		return fmt.tprintf("%d weeks ago", d / 7)
	case:
		return fmt.tprintf("%d months ago", d / 30)
	}
}

service_related :: proc(c: models.Contact, limit: int) -> ([]models.Contact, Store_Error) {
	all, err := repository.repo_list()
	out := make([dynamic]models.Contact, context.temp_allocator)
	for other in all {
		if other.id == c.id {
			continue
		}
		if other.role == c.role {
			append(&out, other)
			if len(out) >= limit {
				break
			}
		}
	}
	return out[:], err
}

// ---- contacts: reads and writes ------------------------------------------
//
// The controllers reach the store only through these: one place to validate,
// and one seam between what a request asked for and how it is stored.

get_contact :: proc(id: int) -> (models.Contact, Store_Error) {
	return repository.repo_get(id)
}

// Everything the detail drawer shows, or the first store error on the way.
Detail :: struct {
	contact:  models.Contact,
	timeline: []models.Interaction,
	related:  []models.Contact,
}

contact_detail :: proc(id: int) -> (d: Detail, err: Store_Error) {
	d.contact = repository.repo_get(id) or_return
	d.timeline = service_timeline(d.contact) or_return
	d.related = service_related(d.contact, 4) or_return
	return
}

// Trim + validate, then insert. A rejected contact comes back as per-field
// messages (the user's to fix) and nothing is stored; a store failure comes
// back as an error (the server's). notes is optional: "" is stored as "".
create_contact :: proc(name, email: string, role: models.Role, status: models.Status, score: int, notes := "", notify := false) -> (models.Contact, []Field_Error, Store_Error) {
	if errs := validate_contact(name, email, notes); len(errs) > 0 {
		return {}, errs, .None
	}
	c, err := repository.repo_create(strings.trim_space(name), strings.trim_space(email), role, status, clamp(score, 0, 100), strings.trim_space(notes), notify)
	return c, nil, err
}

// The full edit from the detail drawer. A missing id is .Not_Found; rejected
// input comes back with the stored contact, unchanged.
update_contact :: proc(id: int, name, email: string, role: models.Role, status: models.Status, score: int) -> (c: models.Contact, errs: []Field_Error, err: Store_Error) {
	if errs = validate_contact(name, email); len(errs) > 0 {
		c, err = repository.repo_get(id)
		return
	}
	c, err = repository.repo_update(id, strings.trim_space(name), strings.trim_space(email), role, status, clamp(score, 0, 100))
	return
}

// Advance the status one step round the cycle (Active → Invited → Disabled → …).
cycle_status :: proc(id: int) -> (models.Contact, Store_Error) {
	return repository.repo_cycle_status(id)
}

delete_contact :: proc(id: int) -> Store_Error {
	return repository.repo_delete(id)
}

// ---- dashboard ----------------------------------------------------------

// The dashboard's cards: counts, shares and spreads, all from one aggregate
// query, so its cost doesn't grow with the table. The spreads feed the
// sparklines: distributions, lowest band first, never invented trends.
Stats :: struct {
	total, active, invited, avg_score: int,
	active_pct, invited_pct:           int, // of the total
	by_role:                           []int, // contacts per role, in Role order
	spread, spread_active, spread_invited: []int, // engagement, lowest band first
}

dashboard_stats :: proc() -> (s: Stats, err: Store_Error) {
	cs := repository.repo_contact_stats() or_return
	for n in cs.by_status {
		s.total += n
	}
	s.active, s.invited = cs.by_status[.Active], cs.by_status[.Invited]
	if s.total > 0 {
		s.avg_score = cs.score_sum / s.total
		s.active_pct = s.active * 100 / s.total
		s.invited_pct = s.invited * 100 / s.total
	}
	s.by_role = make([]int, len(models.Role), context.temp_allocator)
	for n, r in cs.by_role {
		s.by_role[int(r)] = n
	}
	s.spread = make([]int, models.SCORE_BANDS, context.temp_allocator)
	for bands in cs.by_score {
		for n, i in bands {
			s.spread[i] += n
		}
	}
	s.spread_active = slice.clone(cs.by_score[.Active][:], context.temp_allocator)
	s.spread_invited = slice.clone(cs.by_score[.Invited][:], context.temp_allocator)
	return
}

// ---- validation ---------------------------------------------------------

// Field limits, in characters. Roomy for real data, small enough that one
// request can't park megabytes in the store and in every page that renders it.
// The inputs carry the same numbers as `maxlength`, so the browser stops first.
MAX_NAME :: 100
MAX_EMAIL :: 254 // the longest address SMTP can carry (RFC 5321)
MAX_NOTES :: 1000

Field_Error :: struct {
	field: string,
	msg:   string,
}

valid_email :: proc(s: string) -> bool {
	at := strings.index_byte(s, '@')
	if at <= 0 {
		return false
	}
	dot := strings.last_index_byte(s, '.')
	return dot > at + 1 && dot < len(s) - 1
}

validate_contact :: proc(name, email: string, notes := "") -> []Field_Error {
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

field_error :: proc(errs: []Field_Error, field: string) -> (string, bool) {
	for e in errs {
		if e.field == field {
			return e.msg, true
		}
	}
	return "", false
}
