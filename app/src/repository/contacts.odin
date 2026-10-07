package repository

import "../models"
import "../sqlite"

import "core:c"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:sync"

// ---- contacts table -----------------------------------------------------
//
// The original entity. The repo_* (the storage contract) live here; the shared
// connection/lock and the bind/scan/exec helpers come from db.odin.
//
// Every list is filtered, sorted, paged and counted by SQLite, and only the
// rows asked for are copied out: the cost of a request follows the page size,
// not the table. (Loading the whole table into Odin to do it took a 20k-row
// table to ~100-260 ms a request, under the global lock.)

@(private = "file") q_get, q_create, q_update, q_cycle, q_delete, q_count, q_stats: sqlite.Stmt
@(private = "file") q_match, q_filter_count, q_related: sqlite.Stmt
// One prepared statement per sort key and direction: ORDER BY can't be bound.
@(private = "file") q_page: [Contact_Sort][2]sqlite.Stmt

@(private = "file") COLUMNS :: "id,name,email,role,status,score,notes,notify"
@(private = "file") SQL_GET: cstring : "SELECT " + COLUMNS + " FROM contacts WHERE id=? LIMIT 1"
@(private = "file") SQL_CREATE: cstring : "INSERT INTO contacts(name,email,role,status,score,notes,notify) VALUES(?,?,?,?,?,?,?)"
@(private = "file") SQL_UPDATE: cstring : "UPDATE contacts SET name=?,email=?,role=?,status=?,score=? WHERE id=?"
// One statement, so two clicks at once advance the status twice instead of both
// reading the same value and writing the same next one. ?2 is len(models.Status).
@(private = "file") SQL_CYCLE: cstring : "UPDATE contacts SET status=(status+1)%?2 WHERE id=?1"
@(private = "file") SQL_DELETE: cstring : "DELETE FROM contacts WHERE id=?"
@(private = "file") SQL_COUNT: cstring : "SELECT count(*) FROM contacts"
// At most |Status| x |Role| x SCORE_BANDS rows, however big the table is.
@(private = "file") SQL_STATS: cstring : "SELECT status, role, score*?1/101, count(*), sum(score) FROM contacts GROUP BY 1, 2, 3"
@(private = "file") SQL_RELATED: cstring : "SELECT " + COLUMNS + " FROM contacts WHERE role=?1 AND id<>?2 ORDER BY id LIMIT ?3"

// The table's filter, the same in every list query: one status (?4), or -1 for
// any; and q (?1) in a role (?2) or status (?3) label, which the caller works
// out as a bitmask, or in the name or the email (contains_ci, registered in
// db.odin).
// The cheap tests come first: SQLite evaluates them left to right.
@(private = "file") WHERE :: `WHERE (?4 < 0 OR status = ?4) AND (?1 = '' OR (?2 >> role) & 1 OR (?3 >> status) & 1 OR contains_ci(name, ?1) OR contains_ci(email, ?1))`
@(private = "file") SQL_MATCH: cstring : "SELECT " + COLUMNS + " FROM contacts " + WHERE + " ORDER BY id LIMIT ?5"
@(private = "file") SQL_FILTER_COUNT: cstring : "SELECT count(*) FROM contacts " + WHERE

Contact_Filter :: struct {
	q:           string,
	role_mask:   u32, // bit r set: role r's label matches q
	status_mask: u32, // bit s set: status s's label matches q
	status:      int, // only this status; -1 for any
}

Contact_Sort :: enum {
	Name,
	Email,
	Role, // by label, A→Z, as the column shows it
	Status, // by label, A→Z
	Score,
}

@(private)
prepare_contacts :: proc() {
	prep(SQL_GET, &q_get)
	prep(SQL_CREATE, &q_create);prep(SQL_UPDATE, &q_update)
	prep(SQL_CYCLE, &q_cycle);prep(SQL_DELETE, &q_delete)
	prep(SQL_COUNT, &q_count);prep(SQL_STATS, &q_stats)
	prep(SQL_MATCH, &q_match);prep(SQL_FILTER_COUNT, &q_filter_count);prep(SQL_RELATED, &q_related)
	for &by_dir, key in q_page {
		for &st, desc in by_dir {
			// id breaks ties, so a page boundary never splits equal rows unpredictably.
			dir := desc == 1 ? "DESC" : "ASC"
			sql := fmt.tprintf("SELECT %s FROM contacts %s ORDER BY %s %s, id %s LIMIT ?5 OFFSET ?6", COLUMNS, WHERE, order_by(key), dir, dir)
			prep(csql(sql), &st)
		}
	}
}

@(private)
finalize_contacts :: proc() {
	for st in ([]sqlite.Stmt{q_get, q_create, q_update, q_cycle, q_delete, q_count, q_stats, q_match, q_filter_count, q_related}) {
		sqlite.finalize(st)
	}
	for by_dir in q_page {
		for st in by_dir {
			sqlite.finalize(st)
		}
	}
}

// The ORDER BY expression for a sort key. Role and status are stored as their
// enum value but shown by label, so they sort by the label's rank, a CASE
// derived from the label tables rather than written out.
@(private = "file")
order_by :: proc(key: Contact_Sort) -> string {
	rank :: proc(column: string, labels: []string) -> string {
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "CASE %s", column)
		for v, i in labels {
			r := 0 // the label's place in A→Z order: how many labels sort before it
			for other in labels {
				if other < v {r += 1}
			}
			fmt.sbprintf(&b, " WHEN %d THEN %d", i, r)
		}
		strings.write_string(&b, " END")
		return strings.to_string(b)
	}
	switch key {
	case .Name:
		return "name"
	case .Email:
		return "email"
	case .Score:
		return "score"
	case .Role:
		names := models.ROLE_NAMES
		return rank("role", slice.enumerated_array(&names))
	case .Status:
		names := models.STATUS_NAMES
		return rank("status", slice.enumerated_array(&names))
	}
	return "id"
}

// ---- the contract ------------------------------------------------------

// One page of the filtered table, sorted by key, and how many rows match.
repo_page :: proc(f: Contact_Filter, key: Contact_Sort, desc: bool, limit, offset: int) -> (rows: []models.Contact, err: Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	st := q_page[key][desc ? 1 : 0]
	defer sqlite.reset(st)
	bind_filter(st, f)
	sqlite.bind_int64(st, 5, i64(limit));sqlite.bind_int64(st, 6, i64(offset))
	return collect(st)
}

repo_filter_count :: proc(f: Contact_Filter) -> (int, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_filter_count)
	bind_filter(q_filter_count, f)
	err: Error
	if next_row(q_filter_count, &err) {
		return int(sqlite.column_int64(q_filter_count, 0)), .None
	}
	return 0, err
}

// The first `limit` matches in id order: the search dropdown and the JSON API.
repo_match :: proc(f: Contact_Filter, limit: int) -> ([]models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_match)
	bind_filter(q_match, f)
	sqlite.bind_int64(q_match, 5, i64(limit))
	return collect(q_match)
}

// Others with the same role as contact `id`, in id order.
repo_related :: proc(id: int, role: models.Role, limit: int) -> ([]models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_related)
	sqlite.bind_int(q_related, 1, c.int(role));bind_id(q_related, 2, id)
	sqlite.bind_int64(q_related, 3, i64(limit))
	return collect(q_related)
}

repo_get :: proc(id: int) -> (models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	return get_unlocked(id)
}

repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int, notes: string, notify: bool) -> (models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	id, err := create_unlocked(name, email, role, status, score, notes, notify)
	if err != .None {
		return {}, err
	}
	return get_unlocked(id) // read back as the temp-cloned snapshot, atomically
}

repo_update :: proc(id: int, name, email: string, role: models.Role, status: models.Status, score: int) -> (models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_update)
	bind_text(q_update, 1, name);bind_text(q_update, 2, email)
	sqlite.bind_int(q_update, 3, c.int(role));sqlite.bind_int(q_update, 4, c.int(status))
	sqlite.bind_int(q_update, 5, c.int(score));bind_id(q_update, 6, id)
	if err := step_done(q_update); err != .None {
		return {}, err
	}
	if sqlite.changes(db) == 0 {
		return {}, .Not_Found
	}
	return get_unlocked(id)
}

// Advance the status one step round the cycle (Active → Invited → Disabled → …).
repo_cycle_status :: proc(id: int) -> (models.Contact, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_cycle)
	bind_id(q_cycle, 1, id);sqlite.bind_int(q_cycle, 2, c.int(len(models.Status)))
	if err := step_done(q_cycle); err != .None {
		return {}, err
	}
	if sqlite.changes(db) == 0 {
		return {}, .Not_Found
	}
	return get_unlocked(id)
}

// Deleting a contact cascades to its events (events.*_id ON DELETE CASCADE).
repo_delete :: proc(id: int) -> Error {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_delete)
	bind_id(q_delete, 1, id)
	if err := step_done(q_delete); err != .None {
		return err
	}
	return sqlite.changes(db) > 0 ? .None : .Not_Found
}

// Counts by status and role, the score spread per status, and the score sum.
repo_contact_stats :: proc() -> (models.Contact_Stats, Error) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_stats)
	sqlite.bind_int(q_stats, 1, models.SCORE_BANDS)
	out: models.Contact_Stats
	err: Error
	for next_row(q_stats, &err) {
		status := int(sqlite.column_int(q_stats, 0))
		role := int(sqlite.column_int(q_stats, 1))
		band := clamp(int(sqlite.column_int(q_stats, 2)), 0, models.SCORE_BANDS - 1)
		n := int(sqlite.column_int64(q_stats, 3))
		if status < 0 || status >= len(models.Status) || role < 0 || role >= len(models.Role) {
			continue // a row from a newer enum than this binary; skip, don't index past the end
		}
		out.by_status[models.Status(status)] += n
		out.by_role[models.Role(role)] += n
		out.by_score[models.Status(status)][band] += n
		out.score_sum += int(sqlite.column_int64(q_stats, 4))
	}
	return out, err
}

// ---- internals (caller holds the lock) ----------------------------------

@(private = "file")
bind_filter :: proc(st: sqlite.Stmt, f: Contact_Filter) {
	bind_text(st, 1, f.q)
	sqlite.bind_int64(st, 2, i64(f.role_mask));sqlite.bind_int64(st, 3, i64(f.status_mask))
	sqlite.bind_int(st, 4, c.int(f.status))
}

@(private = "file")
collect :: proc(st: sqlite.Stmt) -> ([]models.Contact, Error) {
	out := make([dynamic]models.Contact, context.temp_allocator)
	err: Error
	for next_row(st, &err) {
		append(&out, scan_contact(st))
	}
	return out[:], err
}

@(private = "file")
scan_contact :: proc(st: sqlite.Stmt) -> models.Contact {
	return models.Contact {
		id     = column_id(st, 0),
		name   = clone_col(st, 1),
		email  = clone_col(st, 2),
		role   = models.Role(sqlite.column_int(st, 3)),
		status = models.Status(sqlite.column_int(st, 4)),
		score  = int(sqlite.column_int(st, 5)),
		notes  = clone_col(st, 6),
		notify = sqlite.column_int(st, 7) != 0,
	}
}

@(private = "file")
get_unlocked :: proc(id: int) -> (models.Contact, Error) {
	defer sqlite.reset(q_get)
	bind_id(q_get, 1, id)
	err: Error
	if next_row(q_get, &err) {
		return scan_contact(q_get), .None
	}
	return {}, err == .None ? .Not_Found : err
}

@(private = "file")
create_unlocked :: proc(name, email: string, role: models.Role, status: models.Status, score: int, notes: string, notify: bool) -> (int, Error) {
	defer sqlite.reset(q_create)
	bind_text(q_create, 1, name);bind_text(q_create, 2, email)
	sqlite.bind_int(q_create, 3, c.int(role));sqlite.bind_int(q_create, 4, c.int(status))
	sqlite.bind_int(q_create, 5, c.int(score));bind_text(q_create, 6, notes)
	sqlite.bind_int(q_create, 7, c.int(notify))
	if err := step_done(q_create); err != .None {
		return 0, err
	}
	return int(sqlite.last_insert_rowid(db)), .None
}

// Package-visible to repo_seed (repo.odin); caller holds the lock.
@(private)
count_contacts :: proc() -> int {
	defer sqlite.reset(q_count)
	if sqlite.step(q_count) == sqlite.ROW {
		return int(sqlite.column_int(q_count, 0))
	}
	return 0
}

// Deterministic seed so the demo looks the same on every fresh boot.
@(private)
seed_contacts :: proc() {
	firsts := []string {
		"Ada", "Linus", "Grace", "Dennis", "Margaret", "Alan", "Katherine",
		"Edsger", "Barbara", "Donald", "Radia", "Ken", "Hedy", "Tim",
		"Anita", "John", "Carol", "Vint", "Shafi", "Niklaus",
	}
	lasts := []string {
		"Lovelace", "Torvalds", "Hopper", "Ritchie", "Hamilton", "Turing",
		"Johnson", "Dijkstra", "Liskov", "Knuth", "Perlman", "Thompson",
		"Lamarr", "Berners-Lee", "Borg", "Carmack", "Shaw", "Cerf",
		"Goldwasser", "Wirth",
	}
	for i in 0 ..< len(firsts) {
		first := firsts[i]
		last := lasts[i % len(lasts)]
		email := strings.to_lower(
			strings.concatenate({first, ".", last, "@example.dev"}, context.temp_allocator),
			context.temp_allocator,
		)
		name := strings.concatenate({first, " ", last}, context.temp_allocator)
		role := models.Role((i * 7 + 3) % len(models.Role))
		status := models.Status(i % len(models.Status))
		score := 35 + (i * 53) % 64
		if _, err := create_unlocked(name, email, role, status, score, "", false); err != .None {
			fatal("seed")
		}
	}
}
