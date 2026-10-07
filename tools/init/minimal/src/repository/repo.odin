package repository

import "core:sync"

// ---- repository: this app's store ---------------------------------------
//
// The app-specific wiring over the SQLite plumbing in db.odin (the connection,
// its lock, the migration runner and the bind/scan helpers): which migrations
// make the schema, which tables prepare their statements at boot, and the seed.
// Each table lives in its own file — notes.odin — owning its statements.

// The schema, in order (see migrate in db.odin). #load'd so it rides inside
// the binary. To grow it, add 0002_*.sql and list it here; never edit a file
// that has shipped, since every database records each one's hash.
@(private = "file") MIGRATIONS := [?]Migration {
	{"0001_init.sql", #load("migrations/0001_init.sql", string)},
}

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

// Seed only when empty. main calls it only for a store nobody owns yet
// (:memory:, or SEED=1), so a real store is never refilled. One transaction.
repo_seed :: proc() {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	exec("BEGIN;")
	if count_notes() == 0 {
		seed_notes()
	}
	exec("COMMIT;")
}
