package services

import "../models"
import "../repository"

import "core:fmt"
import "core:strings"
import "core:time"
import "core:unicode/utf8"

// ---- services -----------------------------------------------------------
//
// Business logic over the repository: it returns plain values and never touches
// http. Thin here on purpose — grow it as your domain does. The controllers call
// this layer; this layer calls the repository.

// A store failure, passed up as a value for the controller to answer. Re-
// exported so the controllers need not import the repository.
Store_Error :: repository.Error

// Whether the store answers; /healthz reports it.
store_ok :: proc() -> bool {
	return repository.repo_ping()
}

list_notes :: proc() -> ([]models.Note, Store_Error) {
	return repository.repo_list_notes()
}

// The longest note, in characters. Small enough that one request can't park
// megabytes in the store and in every page that lists it; the input carries the
// same number as `maxlength`.
MAX_NOTE :: 500

// Trim + validate, then persist. `problem` says why the input was rejected
// (the user's to fix); `err` is a store failure (the server's).
create_note :: proc(body: string) -> (note: models.Note, problem: string, err: Store_Error) {
	trimmed := strings.trim_space(body)
	switch {
	case trimmed == "":
		return {}, "Write something first.", .None
	case utf8.rune_count_in_string(trimmed) > MAX_NOTE:
		return {}, fmt.tprintf("A note is at most %d characters.", MAX_NOTE), .None
	}
	note, err = repository.repo_create_note(trimmed)
	return
}

// Relative-time label from a unix timestamp, for display.
time_ago :: proc(at: i64) -> string {
	secs := time.time_to_unix(time.now()) - at
	switch {
	case secs < 60:
		return "just now"
	case secs < 3600:
		return fmt.tprintf("%d min ago", secs / 60)
	case secs < 86400:
		return fmt.tprintf("%d h ago", secs / 3600)
	case:
		return fmt.tprintf("%d d ago", secs / 86400)
	}
}
