package notes_store_sqlite

// ---- notes in SQLite ------------------------------------------------------------------------
//
// Reads on the loop's reader; an add goes through the writer task and reads the
// row back inside its batch, so the caller answers with exactly what was stored.

import "core:strings"
import "core:time"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/notes/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_notes.sql", #load("migrations/0001_notes.sql", string)},
}

@(private) SQL_RECENT :: "SELECT id, body, at FROM notes ORDER BY id DESC LIMIT ?"
@(private) SQL_ADD :: "INSERT INTO notes(body, at) VALUES(?, ?)"
@(private) SQL_COUNT :: "SELECT count(*) FROM notes"

recent :: proc(limit: int, out: ^[dynamic]m.Note) -> m.Error {
	q := db.read(SQL_RECENT)
	defer db.reset(q)
	db.bind_int(q, 1, limit)
	err: store.Error
	for db.next_row(q, &err) {
		append(out, m.Note{id = db.column_id(q, 0), body = db.clone_col(q, 1), at = db.column_id(q, 2)})
	}
	return err
}

add :: proc(op: ^m.Add) -> bool {
	op.run = run_add
	return db.write(op)
}

@(private)
run_add :: proc(o: ^store.Op) {
	op := (^m.Add)(o)
	at := time.time_to_unix(time.now())
	st := db.writer_stmt(SQL_ADD)
	defer db.reset(st)
	db.bind_text(st, 1, op.body)
	db.bind_id(st, 2, at)
	if o.err = db.step_done(st); o.err != .None { return }
	// The row as stored, its strings in the op's own memory.
	op.result = {id = db.last_insert_id(), body = strings.clone(op.body, store.op_allocator(o)), at = at}
}

// The starter's three sample notes, into an empty table only.
seed :: proc() {
	db.write_now(proc() -> bool {
		q := db.writer_stmt(SQL_COUNT)
		err: store.Error
		n := db.column_int(q, 0) if db.next_row(q, &err) else -1
		db.reset(q)
		if n != 0 { return n > 0 }
		now := time.time_to_unix(time.now())
		for body, i in SAMPLES {
			st := db.writer_stmt(SQL_ADD)
			db.bind_text(st, 1, body)
			db.bind_id(st, 2, now - i64(len(SAMPLES) - 1 - i) * 3600)
			ok := db.step_done(st) == .None
			db.reset(st)
			if !ok { return false }
		}
		return true
	})
}

SAMPLES := [?]string {
	"Notes live in a store: app/stores/sqlite/notes here, app/stores/memory/notes in a memory build.",
	"Build your thing in app/features: a feature is its models, domain, views and web packages.",
	"Welcome — this is your minimal starter.",
}
