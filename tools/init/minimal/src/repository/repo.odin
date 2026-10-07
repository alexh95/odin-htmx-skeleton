package repository

import "core:sync"

// ---- repository: this app's store ---------------------------------------
//
// The app-specific wiring over the SQLite plumbing in db.odin (the connection,
// its lock, the migration runner and the bind/scan helpers): which migrations
// make the schema, which tables prepare their statements at boot, and the seed.
// Each table lives in its own file — notes.odin — owning its statements.

// Applied in order at boot; index i == migration #(i+1). #load'd so they ride
// inside the binary. Add 0002_*.sql here to grow the schema.
@(private = "file") MIGRATIONS := [?]string{#load("migrations/0001_init.sql", string)}

// ---- lifecycle (called from main, around repo_seed) ---------------------

repo_open :: proc(path: string) {
	db_open(path)
	migrate(MIGRATIONS[:])
	prepare_notes()
}

repo_close :: proc() {
	finalize_notes()
	db_close()
}

// Seed only when empty, so a persistent DB isn't duplicated. One transaction.
repo_seed :: proc() {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	exec("BEGIN;")
	if count_notes() == 0 {
		seed_notes()
	}
	exec("COMMIT;")
}
