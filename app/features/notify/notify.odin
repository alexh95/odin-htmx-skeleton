package notify

// ---- notify: the domain (PLAN §14.2, §6.2) -----------------------------------------------
//
// The Inbox: producers hand notify_web.send a member's id, their namespaced kind,
// what it points at and its line of HTML; notify keeps the newest KEEP per member and
// lets read ones go after READ_FOR. Plain values and errors, never HTTP.

import "core:strings"
import "core:time"

import "../../platform/escape"
import m "models"
import notify_store "store:notify"

// Per member: the newest stay, the oldest go (D36).
KEEP :: 200

// How long a read notification stays.
READ_FOR :: 30 * 24 * time.Hour

// A producer's line: bounded, so a producer's bug can't park megabytes per member.
MAX_HTML :: 4096
MAX_REF :: 512

// How many a page lists.
SHOWN :: 50

list :: proc(user: u64, out: ^[dynamic]m.Item) -> m.Error {
	return notify_store.list(user, SHOWN, out)
}

unread :: proc(user: u64) -> int {
	return notify_store.unread(user)
}

// What a producer may send: a member, a kind `<feature>.<name>` in [a-z0-9_.], a
// ref on this site, a bounded line. "" when it may.
check :: proc(user: u64, kind, ref, html: string) -> string {
	switch {
	case user == 0:                                            return "no member"
	case !valid_kind(kind):                                    return "a kind is <feature>.<name>"
	case len(ref) > MAX_REF, ref != "" && !escape.site_path(ref): return "a ref is a path on this site"
	case len(html) == 0, len(html) > MAX_HTML:                 return "a line is 1 to 4096 bytes"
	}
	return ""
}

// Stores op's item; op.done runs once it is. false: the store is busy.
add :: proc(op: ^m.Add) -> bool {
	return notify_store.add(op)
}

mark_read :: proc(user: u64) -> m.Error {
	return notify_store.mark_read(user)
}

// The hourly sweep: read items older than READ_FOR go.
prune :: proc() -> int {
	return notify_store.prune(time.time_to_unix(time.now()) - i64(READ_FOR / time.Second))
}

@(private)
valid_kind :: proc(kind: string) -> bool {
	dot := strings.index_byte(kind, '.')
	if dot <= 0 || dot == len(kind) - 1 || len(kind) > 64 { return false }
	for c in transmute([]byte)kind {
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '_', '.':
		case:
			return false
		}
	}
	return true
}
