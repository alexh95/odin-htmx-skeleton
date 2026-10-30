package jobs_store_sqlite

// ---- jobs in SQLite ------------------------------------------------------------------------
//
// The sync's writes go through write_now on the scheduler's thread, one transaction per sync
// (the writer's lock orders them with the writer task's batches); the page's reads are the
// loop's reader.

import "base:builtin"

import "../../../platform/store"
import db "../../../platform/store/sqlite"
import m "../../../features/jobs/models"

IMPL :: "sqlite"

MIGRATIONS := [?]store.Migration {
	{1, "0001_jobs.sql", #load("migrations/0001_jobs.sql", string)},
}

@(private) COLS :: "boot, id, job, state, by_hand, queued_at, started_at, ended_at, done, total, log, note, lease_until"
@(private) SQL_SAVE :: "INSERT INTO jobs_runs(" + COLS + ") VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " +
	"ON CONFLICT(boot, id) DO UPDATE SET state = excluded.state, started_at = excluded.started_at, ended_at = excluded.ended_at, " +
	"done = excluded.done, total = excluded.total, log = excluded.log, note = excluded.note, lease_until = excluded.lease_until"
@(private) SQL_RECENT :: "SELECT boot, id, job, state, by_hand, queued_at, started_at, ended_at, done, total, '', note, lease_until FROM jobs_runs ORDER BY queued_at DESC, id DESC LIMIT ?"
@(private) SQL_RUN :: "SELECT " + COLS + " FROM jobs_runs WHERE boot = ? AND id = ?"
@(private) SQL_FAIL_LAPSED :: "UPDATE jobs_runs SET state = 'failed', ended_at = ?2, note = 'interrupted by a restart', lease_until = 0 " +
	"WHERE state IN ('queued', 'running') AND boot != ?1 AND lease_until < ?2"
@(private) SQL_PRUNE :: "DELETE FROM jobs_runs WHERE ended_at != 0 AND ended_at < ?"

@(private)
pending: []m.Run_Row // write_now's run takes no data: the rows of the save under way, under the writer's lock

save :: proc(rows: []m.Run_Row) -> m.Error {
	if len(rows) == 0 { return .None }
	pending = rows
	ok := db.write_now(proc() -> bool {
		for r in pending {
			st := db.writer_stmt(SQL_SAVE)
			db.bind_id(st, 1, r.boot)
			db.bind_id(st, 2, r.id)
			db.bind_text(st, 3, r.job)
			db.bind_text(st, 4, r.state)
			db.bind_bool(st, 5, r.by_hand)
			db.bind_id(st, 6, r.queued_at)
			db.bind_id(st, 7, r.started_at)
			db.bind_id(st, 8, r.ended_at)
			db.bind_id(st, 9, r.done)
			db.bind_id(st, 10, r.total)
			db.bind_text(st, 11, r.log)
			db.bind_text(st, 12, r.note)
			db.bind_id(st, 13, r.lease_until)
			err := db.step_done(st)
			db.reset(st)
			if err != .None { return false }
		}
		return true
	})
	pending = nil
	return .None if ok else .Failed
}

recent :: proc(limit: int, into: ^[dynamic]m.Run_Row) -> (err: m.Error) {
	q := db.read(SQL_RECENT)
	defer db.reset(q)
	db.bind_int(q, 1, limit)
	for db.next_row(q, &err) { builtin.append(into, row(q)) }
	return
}

run :: proc(boot, id: i64) -> (r: m.Run_Row, err: m.Error) {
	q := db.read(SQL_RUN)
	defer db.reset(q)
	db.bind_id(q, 1, boot)
	db.bind_id(q, 2, id)
	if !db.next_row(q, &err) { return {}, .Not_Found if err == .None else err }
	return row(q), .None
}

@(private)
lapsed: struct {
	boot, now: i64,
	n:         int,
}

fail_lapsed :: proc(boot, now: i64) -> (int, m.Error) {
	lapsed.boot, lapsed.now, lapsed.n = boot, now, 0
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_FAIL_LAPSED)
		defer db.reset(st)
		db.bind_id(st, 1, lapsed.boot)
		db.bind_id(st, 2, lapsed.now)
		if db.step_done(st) != .None { return false }
		lapsed.n = db.changes()
		return true
	})
	return lapsed.n, .None if ok else .Failed
}

@(private)
pruning: struct {
	before: i64,
	n:      int,
}

prune :: proc(before: i64) -> (int, m.Error) {
	pruning.before, pruning.n = before, 0
	ok := db.write_now(proc() -> bool {
		st := db.writer_stmt(SQL_PRUNE)
		defer db.reset(st)
		db.bind_id(st, 1, pruning.before)
		if db.step_done(st) != .None { return false }
		pruning.n = db.changes()
		return true
	})
	return pruning.n, .None if ok else .Failed
}

@(private)
row :: proc(q: db.Stmt) -> m.Run_Row {
	return m.Run_Row {
		boot = db.column_id(q, 0), id = db.column_id(q, 1), job = db.clone_col(q, 2), state = db.clone_col(q, 3),
		by_hand = db.column_bool(q, 4), queued_at = db.column_id(q, 5), started_at = db.column_id(q, 6),
		ended_at = db.column_id(q, 7), done = db.column_id(q, 8), total = db.column_id(q, 9), log = db.clone_col(q, 10),
		note = db.clone_col(q, 11), lease_until = db.column_id(q, 12),
	}
}
