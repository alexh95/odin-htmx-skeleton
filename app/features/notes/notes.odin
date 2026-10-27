package notes

// ---- notes: the domain -----------------------------------------------------------------
//
// One small entity, the minimal starter's (`init --minimal` made it in the
// skeleton): a list of the newest notes and a form that adds one. Plain values
// and errors, never HTTP.

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

import m "models"
import notes_store "store:notes"

// How many notes a page lists: the newest. A list that grows without a bound
// makes every page view slower than the last.
SHOWN :: 50

// The longest note, in characters: small enough that one request can't park
// megabytes in the store and in every page that lists it. The input carries the
// same number as maxlength.
MAX_NOTE :: 500

recent :: proc(out: ^[dynamic]m.Note) -> m.Error {
	return notes_store.recent(SHOWN, out)
}

// The trimmed note, or why it was refused (the user's to fix).
check :: proc(body: string) -> (trimmed: string, problem: string) {
	trimmed = strings.trim_space(body)
	switch {
	case trimmed == "":
		return "", "Write something first."
	case utf8.rune_count_in_string(trimmed) > MAX_NOTE:
		return "", fmt.tprintf("A note is at most %d characters.", MAX_NOTE)
	}
	return trimmed, ""
}

// Stores op.body; op.done runs once it is. false: the store is busy.
add :: proc(op: ^m.Add) -> bool {
	return notes_store.add(op)
}

// The demo rows, into an empty store only.
seed :: proc() {
	notes_store.seed()
}
