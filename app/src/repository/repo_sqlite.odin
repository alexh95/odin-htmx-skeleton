package repository

import "../models"
import "../sqlite"

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

// ---- repository (SQLite) ------------------------------------------------
//
// Persistent store over the SQLite amalgamation. The 7-proc contract
// (repo_list/get/create/update/set_status/delete/seed) is unchanged; everything
// above (services/views/controllers) is untouched. Backend chosen by DB_PATH:
// ":memory:" (the test/dev default — a real in-RAM SQLite, seeded fresh per
// boot, gone on exit) or a real file path in prod.
//
// Allocator discipline is identical to the old in-memory snapshot(): every
// string handed back is cloned into context.temp_allocator inside scan_contact,
// so nothing returned points into a statement buffer that a later step/reset
// could invalidate.
//
// Concurrency v1: ONE shared connection, guarded by the exclusive RW_Mutex lock
// for EVERY op. A single connection's prepared statements are shared mutable
// state, so concurrent (shared-lock) reads would corrupt each other's iteration
// — correctness requires serializing. Shared (parallel) reads come back when we
// move to per-thread WAL connections, the optimization deferred until the load
// tests demand it (see docs/DATA_IMPL.md §4). The RW_Mutex type is kept for
// exactly that future.

@(private = "file") db: sqlite.DB
@(private = "file") lock: sync.RW_Mutex
@(private = "file") q_list, q_get, q_create, q_update, q_set_status, q_delete, q_count: sqlite.Stmt

@(private = "file") SCHEMA := #load("migrations/0001_init.sql", string)

@(private = "file") SQL_LIST: cstring : "SELECT id,name,email,role,status,score FROM contacts ORDER BY id"
@(private = "file") SQL_GET: cstring : "SELECT id,name,email,role,status,score FROM contacts WHERE id=? LIMIT 1"
@(private = "file") SQL_CREATE: cstring : "INSERT INTO contacts(name,email,role,status,score) VALUES(?,?,?,?,?)"
@(private = "file") SQL_UPDATE: cstring : "UPDATE contacts SET name=?,email=?,role=?,status=?,score=? WHERE id=?"
@(private = "file") SQL_SET_STATUS: cstring : "UPDATE contacts SET status=? WHERE id=?"
@(private = "file") SQL_DELETE: cstring : "DELETE FROM contacts WHERE id=?"
@(private = "file") SQL_COUNT: cstring : "SELECT count(*) FROM contacts"

// ---- lifecycle (called from main, next to repo_seed) --------------------

repo_open :: proc(path: string) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	if sqlite.open_v2(cpath, &db, sqlite.OPEN_READWRITE | sqlite.OPEN_CREATE, nil) != sqlite.OK {
		fatal("open")
	}
	exec("PRAGMA journal_mode=WAL;") // many readers + one writer (a no-op on :memory:)
	exec("PRAGMA busy_timeout=5000;") // wait, don't fail, on a brief write lock
	exec("PRAGMA foreign_keys=ON;")
	exec("PRAGMA synchronous=NORMAL;") // safe under WAL, much faster than FULL
	migrate()
	prep(SQL_LIST, &q_list);prep(SQL_GET, &q_get)
	prep(SQL_CREATE, &q_create);prep(SQL_UPDATE, &q_update)
	prep(SQL_SET_STATUS, &q_set_status);prep(SQL_DELETE, &q_delete)
	prep(SQL_COUNT, &q_count)
}

// ---- contract (unchanged signatures) ------------------------------------

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

repo_delete :: proc(id: int) -> bool {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_delete)
	sqlite.bind_int(q_delete, 1, c.int(id))
	sqlite.step(q_delete)
	return sqlite.changes(db) > 0
}

// Same deterministic data as before, but it seeds only an EMPTY store, so a
// persistent file DB isn't duplicated on every boot. A fresh :memory: DB (tests)
// is always empty, so it seeds exactly like today. One transaction = one fsync.
repo_seed :: proc() {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	if count_unlocked() > 0 {
		return
	}

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

	exec("BEGIN;")
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
	exec("COMMIT;")
}

// ---- internals (caller holds the lock) ----------------------------------

@(private = "file")
scan_contact :: proc(st: sqlite.Stmt) -> models.Contact {
	return models.Contact {
		id = int(sqlite.column_int(st, 0)),
		name = clone_col(st, 1), // cloned into temp arena — never aliases the stmt buffer
		email = clone_col(st, 2),
		role = models.Role(sqlite.column_int(st, 3)),
		status = models.Status(sqlite.column_int(st, 4)),
		score = int(sqlite.column_int(st, 5)),
	}
}

@(private = "file")
clone_col :: proc(st: sqlite.Stmt, col: c.int) -> string {
	return strings.clone_from_cstring(sqlite.column_text(st, col), context.temp_allocator)
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

@(private = "file")
count_unlocked :: proc() -> int {
	defer sqlite.reset(q_count)
	if sqlite.step(q_count) == sqlite.ROW {
		return int(sqlite.column_int(q_count, 0))
	}
	return 0
}

@(private = "file")
bind_text :: proc(st: sqlite.Stmt, idx: c.int, s: string) {
	sqlite.bind_text(st, idx, raw_data(s), c.int(len(s)), sqlite.TRANSIENT)
}

@(private = "file")
exec :: proc(sql: cstring) {
	if sqlite.exec(db, sql, nil, nil, nil) != sqlite.OK {
		fatal("exec")
	}
}

@(private = "file")
prep :: proc(sql: cstring, out: ^sqlite.Stmt) {
	if sqlite.prepare_v2(db, sql, -1, out, nil) != sqlite.OK {
		fatal("prepare")
	}
}

// Plain SQL migrations applied in order at boot; a schema_version row records
// the highest applied number. One migration today; add 0002_*.sql and append it
// to the list to grow the schema.
@(private = "file")
migrate :: proc() {
	exec("CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL);")
	cur := count_version()
	migrations := []cstring{csql(SCHEMA)} // index 0 == migration #1
	for i in cur ..< len(migrations) {
		exec(migrations[i])
		exec(csql(fmt.tprintf("INSERT INTO schema_version(version) VALUES(%d);", i + 1)))
	}
}

@(private = "file")
count_version :: proc() -> int {
	st: sqlite.Stmt
	prep("SELECT coalesce(max(version),0) FROM schema_version", &st)
	defer sqlite.finalize(st)
	if sqlite.step(st) == sqlite.ROW {
		return int(sqlite.column_int(st, 0))
	}
	return 0
}

@(private = "file")
csql :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

@(private = "file")
fatal :: proc(what: string) {
	fmt.eprintfln("sqlite %s failed: %s", what, sqlite.errmsg(db))
	os.exit(1)
}
