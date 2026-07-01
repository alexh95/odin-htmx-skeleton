package services

import "../models"
import "../repository"

import "core:fmt"
import "core:strings"
import "core:time"

// ---- services -----------------------------------------------------------
//
// Business logic over the repository: it returns plain values and never touches
// http. Thin here on purpose — grow it as your domain does. The controllers call
// this layer; this layer calls the repository.

list_notes :: proc() -> []models.Note {
	return repository.repo_list_notes()
}

// Trim + validate, then persist. `ok` is false for an empty note.
create_note :: proc(body: string) -> (models.Note, bool) {
	trimmed := strings.trim_space(body)
	if trimmed == "" {
		return {}, false
	}
	return repository.repo_create_note(trimmed), true
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
