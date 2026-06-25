package demo

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
	rows:        []Contact,
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

contact_matches :: proc(c: Contact, q: string) -> bool {
	if q == "" {
		return true
	}
	role := ROLE_NAMES
	status := STATUS_NAMES
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
	filtered := make([dynamic]Contact, context.temp_allocator)
	for c in repo_list() {
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
sort_contacts :: proc(rows: []Contact, sort: string) {
	key := sort
	desc := false
	if strings.has_suffix(sort, "_desc") {
		desc = true
		key = sort[:len(sort) - len("_desc")]
	}

	switch key {
	case "email":
		slice.sort_by(rows, proc(a, b: Contact) -> bool { return a.email < b.email })
	case "role":
		slice.sort_by(rows, proc(a, b: Contact) -> bool {
			names := ROLE_NAMES
			return names[a.role] < names[b.role]
		})
	case "status":
		slice.sort_by(rows, proc(a, b: Contact) -> bool {
			names := STATUS_NAMES
			return names[a.status] < names[b.status]
		})
	case "score":
		slice.sort_by(rows, proc(a, b: Contact) -> bool { return a.score < b.score })
	case: // "name" and anything unrecognised
		slice.sort_by(rows, proc(a, b: Contact) -> bool { return a.name < b.name })
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

service_search :: proc(q: string, limit: int) -> []Contact {
	out := make([dynamic]Contact, context.temp_allocator)
	if strings.trim_space(q) == "" {
		return out[:]
	}
	for c in repo_list() {
		if contact_matches(c, q) {
			append(&out, c)
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
