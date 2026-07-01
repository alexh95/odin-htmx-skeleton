package repository

import "../models"
import "../sqlite"

import "core:c"
import "core:sync"
import "core:time"

// ---- notes table --------------------------------------------------------
//
// The one entity's storage — your example to copy. Statements are prepared once
// (prepare_notes, called from repo_open) and every op takes the shared lock in
// repo.odin. Text columns are cloned into the request arena (clone_col) so a
// returned string never aliases a statement buffer.

@(private = "file") q_list, q_create, q_count: sqlite.Stmt

@(private = "file") SQL_LIST: cstring : "SELECT id,body,at FROM notes ORDER BY id DESC"
@(private = "file") SQL_CREATE: cstring : "INSERT INTO notes(body,at) VALUES(?,?)"
@(private = "file") SQL_COUNT: cstring : "SELECT count(*) FROM notes"

@(private)
prepare_notes :: proc() {
	prep(SQL_LIST, &q_list)
	prep(SQL_CREATE, &q_create)
	prep(SQL_COUNT, &q_count)
}

@(private)
finalize_notes :: proc() {
	sqlite.finalize(q_list)
	sqlite.finalize(q_create)
	sqlite.finalize(q_count)
}

// Newest first.
repo_list_notes :: proc() -> []models.Note {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_list)
	out := make([dynamic]models.Note, context.temp_allocator)
	for sqlite.step(q_list) == sqlite.ROW {
		append(
			&out,
			models.Note {
				id = int(sqlite.column_int(q_list, 0)),
				body = clone_col(q_list, 1),
				at = sqlite.column_int64(q_list, 2),
			},
		)
	}
	return out[:]
}

repo_create_note :: proc(body: string) -> models.Note {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_create)
	at := time.time_to_unix(time.now())
	bind_text(q_create, 1, body)
	sqlite.bind_int64(q_create, 2, at)
	sqlite.step(q_create)
	return models.Note{id = int(sqlite.last_insert_rowid(db)), body = body, at = at}
}

// Package-visible to repo_seed (repo.odin); caller holds the lock.
@(private)
count_notes :: proc() -> int {
	defer sqlite.reset(q_count)
	if sqlite.step(q_count) == sqlite.ROW {
		return int(sqlite.column_int(q_count, 0))
	}
	return 0
}

@(private)
seed_notes :: proc() {
	now := time.time_to_unix(time.now())
	samples := []string {
		"Welcome — this is your minimal starter.",
		"Edit app/src to build your thing; add tables beside notes.",
		"Notes live in SQLite — see repository/notes.odin.",
	}
	for s, i in samples {
		bind_text(q_create, 1, s)
		sqlite.bind_int64(q_create, 2, now - i64(i) * 3600)
		sqlite.step(q_create)
		sqlite.reset(q_create)
	}
}
