package repository

import "core:sync"

// ---- repository: this app's store ---------------------------------------
//
// The app-specific wiring over the SQLite plumbing in db.odin: which migrations
// make the schema, which tables prepare their statements at boot, and the demo
// seed. Each table lives in its own file — contacts.odin (repo_*) and
// events.odin (event_*) — owning its prepared statements. Nothing above the
// repository knows SQL.

// Applied in order at boot; index i == migration #(i+1). #load'd so they ride
// inside the binary. Add 0003_*.sql here to grow the schema.
@(private = "file") MIGRATIONS := [?]string {
	#load("migrations/0001_init.sql", string),
	#load("migrations/0002_events.sql", string),
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

// Seed both tables, but each only when empty — so a persistent DB isn't
// duplicated, and a DB migrated from contacts-only (e.g. an existing deploy)
// still gets its events backfilled. One transaction = one fsync; events seed
// after contacts so the FK targets exist.
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
