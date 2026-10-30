package audit

// ---- audit: reading the log (PLAN §17.7) ---------------------------------------------------
//
// The writes are `store:audit`'s `append`, which any domain, web or identity package calls
// directly. This domain is the reading side behind /admin/audit: a filtered page, newest
// first, and the same filter as CSV.

import "core:fmt"
import "core:strings"
import "core:time"

import m "models"
import audit_store "store:audit"

// A page of the table, and the most a CSV export carries.
PAGE :: 50
EXPORT_MAX :: 10_000

// A filter value longer than this names nothing the log holds.
MAX_FILTER :: 64

// Whether this build keeps the log at all: the memory family only logs a line per entry.
kept :: proc() -> bool { return audit_store.IMPL != "memory" }

// A filter from a request's values: trimmed, capped, and a page of `limit`.
filter :: proc(actor, action: string, before: i64, limit := PAGE) -> m.Filter {
	cap :: proc(s: string) -> string {
		t := strings.trim_space(s)
		if len(t) <= MAX_FILTER { return t }
		n := MAX_FILTER
		for n > 0 && t[n] & 0xC0 == 0x80 { n -= 1 } // cut by rune, never inside one
		return t[:n]
	}
	return m.Filter{actor = cap(actor), action = cap(action), before = max(before, 0), limit = limit}
}

list :: proc(f: m.Filter, into: ^[dynamic]m.Entry) -> m.Error {
	return audit_store.list(f, into)
}

// "2026-10-30 07:52:12" in UTC, for the table and the CSV.
stamp :: proc(ms: i64) -> string {
	t := time.unix(ms / 1000, 0)
	y, mo, d := time.date(t)
	h, mi, s := time.clock(t)
	return fmt.tprintf("%04d-%02d-%02d %02d:%02d:%02d", y, int(mo), d, h, mi, s)
}

// The entries as CSV (RFC 4180), a header first. A field a spreadsheet would read as a formula
// (=, +, -, @, a tab, a CR) gets a leading quote mark, so an actor's name can't run in it.
write_csv :: proc(b: ^strings.Builder, entries: []m.Entry) {
	strings.write_string(b, "id,at,actor_id,actor,action,target_kind,target_id,reason,client,meta\r\n")
	for e in entries {
		fmt.sbprintf(b, "%d,%s,%d,", e.id, stamp(e.at), e.actor.id)
		field(b, e.actor.name)
		strings.write_byte(b, ',')
		field(b, e.action)
		strings.write_byte(b, ',')
		field(b, e.target.kind)
		fmt.sbprintf(b, ",%d,", e.target.id)
		field(b, e.reason)
		strings.write_byte(b, ',')
		field(b, e.actor.client)
		strings.write_byte(b, ',')
		field(b, e.meta)
		strings.write_string(b, "\r\n")
	}
}

@(private)
field :: proc(b: ^strings.Builder, s: string) {
	formula := len(s) > 0 && strings.index_byte("=+-@\t\r", s[0]) >= 0
	if !formula && strings.index_any(s, ",\"\r\n") < 0 {
		strings.write_string(b, s)
		return
	}
	strings.write_byte(b, '"')
	if formula { strings.write_byte(b, '\'') }
	for c in transmute([]byte)s {
		if c == '"' { strings.write_byte(b, '"') }
		strings.write_byte(b, c)
	}
	strings.write_byte(b, '"')
}
