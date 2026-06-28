package repository

import "../models"
import "../sqlite"

import "core:c"
import "core:strings"
import "core:sync"

// ---- contacts table -----------------------------------------------------
//
// The original entity. The seven repo_* (the storage contract) live here; the
// shared connection/lock and the bind/scan/exec helpers come from repo.odin.

@(private = "file") q_list, q_get, q_create, q_update, q_set_status, q_delete, q_count: sqlite.Stmt

@(private = "file") SQL_LIST: cstring : "SELECT id,name,email,role,status,score FROM contacts ORDER BY id"
@(private = "file") SQL_GET: cstring : "SELECT id,name,email,role,status,score FROM contacts WHERE id=? LIMIT 1"
@(private = "file") SQL_CREATE: cstring : "INSERT INTO contacts(name,email,role,status,score) VALUES(?,?,?,?,?)"
@(private = "file") SQL_UPDATE: cstring : "UPDATE contacts SET name=?,email=?,role=?,status=?,score=? WHERE id=?"
@(private = "file") SQL_SET_STATUS: cstring : "UPDATE contacts SET status=? WHERE id=?"
@(private = "file") SQL_DELETE: cstring : "DELETE FROM contacts WHERE id=?"
@(private = "file") SQL_COUNT: cstring : "SELECT count(*) FROM contacts"

@(private)
prepare_contacts :: proc() {
	prep(SQL_LIST, &q_list);prep(SQL_GET, &q_get)
	prep(SQL_CREATE, &q_create);prep(SQL_UPDATE, &q_update)
	prep(SQL_SET_STATUS, &q_set_status);prep(SQL_DELETE, &q_delete)
	prep(SQL_COUNT, &q_count)
}

@(private)
finalize_contacts :: proc() {
	for st in ([]sqlite.Stmt{q_list, q_get, q_create, q_update, q_set_status, q_delete, q_count}) {
		sqlite.finalize(st)
	}
}

// ---- the contract (signatures unchanged) --------------------------------

repo_list :: proc() -> []models.Contact {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_list)
	out := make([dynamic]models.Contact, context.temp_allocator)
	for sqlite.step(q_list) == sqlite.ROW {
		append(&out, scan_contact(q_list))
	}
	return out[:]
}

repo_get :: proc(id: int) -> (models.Contact, bool) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	return get_unlocked(id)
}

repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> models.Contact {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	id := create_unlocked(name, email, role, status, score)
	c, _ := get_unlocked(id) // read back as the temp-cloned snapshot, atomically
	return c
}

repo_update :: proc(id: int, name, email: string, role: models.Role, status: models.Status, score: int) -> (models.Contact, bool) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_update)
	bind_text(q_update, 1, name);bind_text(q_update, 2, email)
	sqlite.bind_int(q_update, 3, c.int(role));sqlite.bind_int(q_update, 4, c.int(status))
	sqlite.bind_int(q_update, 5, c.int(score));sqlite.bind_int(q_update, 6, c.int(id))
	sqlite.step(q_update)
	if sqlite.changes(db) == 0 {
		return {}, false
	}
	return get_unlocked(id)
}

repo_set_status :: proc(id: int, status: models.Status) -> (models.Contact, bool) {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_set_status)
	sqlite.bind_int(q_set_status, 1, c.int(status));sqlite.bind_int(q_set_status, 2, c.int(id))
	sqlite.step(q_set_status)
	if sqlite.changes(db) == 0 {
		return {}, false
	}
	return get_unlocked(id)
}

// Deleting a contact cascades to its events (events.*_id ON DELETE CASCADE).
repo_delete :: proc(id: int) -> bool {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_delete)
	sqlite.bind_int(q_delete, 1, c.int(id))
	sqlite.step(q_delete)
	return sqlite.changes(db) > 0
}

// ---- internals (caller holds the lock) ----------------------------------

@(private = "file")
scan_contact :: proc(st: sqlite.Stmt) -> models.Contact {
	return models.Contact {
		id     = int(sqlite.column_int(st, 0)),
		name   = clone_col(st, 1),
		email  = clone_col(st, 2),
		role   = models.Role(sqlite.column_int(st, 3)),
		status = models.Status(sqlite.column_int(st, 4)),
		score  = int(sqlite.column_int(st, 5)),
	}
}

@(private = "file")
get_unlocked :: proc(id: int) -> (models.Contact, bool) {
	defer sqlite.reset(q_get)
	sqlite.bind_int(q_get, 1, c.int(id))
	if sqlite.step(q_get) == sqlite.ROW {
		return scan_contact(q_get), true
	}
	return {}, false
}

@(private = "file")
create_unlocked :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> int {
	defer sqlite.reset(q_create)
	bind_text(q_create, 1, name);bind_text(q_create, 2, email)
	sqlite.bind_int(q_create, 3, c.int(role));sqlite.bind_int(q_create, 4, c.int(status))
	sqlite.bind_int(q_create, 5, c.int(score))
	sqlite.step(q_create)
	return int(sqlite.last_insert_rowid(db))
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
		create_unlocked(name, email, role, status, score)
	}
}
