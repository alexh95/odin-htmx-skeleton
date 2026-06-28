package services
import "../repository"
import "../models"

import "core:fmt"
import "core:slice"
import "core:strings"

// ---- services -----------------------------------------------------------
//
// Business logic over the repository: search, sort, paginate, validate. This
// layer returns plain values and never touches http. The list controls all
// funnel through service_page so the table fragment, the page, and any future
// caller share one definition of "what the user is looking at".

PAGE_SIZE :: 7
SEARCH_LIMIT :: 6 // results shown in the nav search dropdown

Page :: struct {
	rows:        []models.Contact,
	page:        int,
	total_pages: int,
	total:       int,
	q:           string,
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
service_page :: proc(q, sort: string, page: int) -> Page {
	filtered := make([dynamic]models.Contact, context.temp_allocator)
	for c in repository.repo_list() {
		if contact_matches(c, q) {
			append(&filtered, c)
		}
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
		sort = sort,
	}
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

service_search :: proc(q: string, limit: int) -> []models.Contact {
	out := make([dynamic]models.Contact, context.temp_allocator)
	if strings.trim_space(q) == "" {
		return out[:]
	}
	for c in repository.repo_list() {
		if contact_matches(c, q) {
			append(&out, c)
			if len(out) >= limit {
				break
			}
		}
	}
	return out[:]
}

// ---- detail view: activity trail + related ------------------------------
//
// The contact detail drills past the table row. There's no persisted event log
// (the store is a POC — see docs/DATA.md), so the activity trail is *derived*
// deterministically from the contact: plausible, stable across reloads, and free
// of store changes. Related = others sharing the role, the only relationship the
// single-entity domain affords.

Activity :: struct {
	icon:  string,
	label: string,
	ago:   string, // `when` is an Odin keyword
}

@(private = "file")
rel_days :: proc(n: int) -> string {
	switch {
	case n <= 0:
		return "today"
	case n == 1:
		return "yesterday"
	case n < 14:
		return fmt.tprintf("%d days ago", n)
	case n < 60:
		return fmt.tprintf("%d weeks ago", n / 7)
	case:
		return fmt.tprintf("%d months ago", n / 30)
	}
}

service_activity :: proc(c: models.Contact) -> []Activity {
	rn := models.ROLE_NAMES
	sn := models.STATUS_NAMES
	out := make([dynamic]Activity, context.temp_allocator)
	append(&out, Activity{"bolt", "Last active session", rel_days(c.id % 6)})
	append(&out, Activity{"check", fmt.tprintf("Engagement updated to %d", c.score), rel_days(7 + c.score % 20)})
	append(&out, Activity{"cycle", fmt.tprintf("Status set to %s", sn[c.status]), rel_days(30 + c.id % 25)})
	append(&out, Activity{"users", fmt.tprintf("Assigned to the %s team", rn[c.role]), rel_days(60 + (c.id * 3) % 40)})
	append(&out, Activity{"plus", "Joined the workspace", rel_days(120 + (c.id * 7) % 240)})
	return out[:]
}

service_related :: proc(c: models.Contact, limit: int) -> []models.Contact {
	out := make([dynamic]models.Contact, context.temp_allocator)
	for other in repository.repo_list() {
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
	return out[:]
}

// ---- validation ---------------------------------------------------------

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

validate_contact :: proc(name, email: string) -> []Field_Error {
	errs := make([dynamic]Field_Error, context.temp_allocator)
	if strings.trim_space(name) == "" {
		append(&errs, Field_Error{"name", "Name is required."})
	}
	if !valid_email(strings.trim_space(email)) {
		append(&errs, Field_Error{"email", "Enter a valid email address."})
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
