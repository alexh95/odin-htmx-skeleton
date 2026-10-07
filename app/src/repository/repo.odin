package repository

import "core:sync"

// ---- repository: this app's store ---------------------------------------
//
// The app-specific wiring over the SQLite plumbing in db.odin: which migrations
// make the schema, which tables prepare their statements at boot, and the demo
// seed. Each table lives in its own file — contacts.odin (repo_*) and
// events.odin (event_*) — owning its prepared statements. Nothing above the
// repository knows SQL.

// The schema, in order (see migrate in db.odin). #load'd so it rides inside
// the binary. To grow it, add 0003_*.sql and list it here; never edit a file
// that has shipped, since every database records each one's hash.
@(private = "file") MIGRATIONS := [?]Migration {
	{"0001_init.sql", #load("migrations/0001_init.sql", string)},
	{"0002_events.sql", #load("migrations/0002_events.sql", string)},
}

// ---- lifecycle (called from main, around repo_seed) ---------------------

repo_open :: proc(path: string) {
	db_open(path)
	migrate(MIGRATIONS[:])
	prepare_contacts()
	prepare_events()
}

// Finalize statements and close the connection. Symmetry with repo_open; wire
// via `defer` in main.
repo_close :: proc() {
	finalize_contacts()
	finalize_events()
	db_close()
}

// Seed both tables, but each only when empty. main calls it only for a store
// nobody owns yet (:memory:, or SEED=1), so a production table emptied on
// purpose is never refilled with demo rows. One transaction = one fsync;
// events seed after contacts so the FK targets exist.
repo_seed :: proc() {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	exec("BEGIN;")
	if count_contacts() == 0 {
		seed_contacts()
	}
	if count_events() == 0 {
		seed_events()
	}
	exec("COMMIT;")
}
