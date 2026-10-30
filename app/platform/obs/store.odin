package obs

// ---- the store's memory ------------------------------------------------------
//
// SQLite is built with MEMSTATUS=0 (D16), so sqlite3_memory_used says nothing; each
// connection's sqlite3_db_status does. platform/store/sqlite pushes them here, the
// writer after each batch and each loop's reader on its 1 s timer, and ops reads the
// sum, so ops never imports the store (§15.4, LC §5).

import "core:sync"

Store_Memory :: struct {
	cache, schema, stmt: i64, // bytes
}

@(private)
store_mem: struct {
	slots:    [MAX_LOOPS + 1][3]i64, // atomic: slot 0 is the writer, 1 + n loop n's reader
	reported: bool, // atomic
}

store_report :: proc "contextless" (slot: int, m: Store_Memory) {
	if slot < 0 || slot >= len(store_mem.slots) { return }
	s := &store_mem.slots[slot]
	sync.atomic_store_explicit(&s[0], m.cache, .Relaxed)
	sync.atomic_store_explicit(&s[1], m.schema, .Relaxed)
	sync.atomic_store_explicit(&s[2], m.stmt, .Relaxed)
	sync.atomic_store_explicit(&store_mem.reported, true, .Relaxed)
}

// The sum over every connection that reported; ok is false in a build with no store.
store_memory :: proc() -> (m: Store_Memory, ok: bool) {
	if !sync.atomic_load_explicit(&store_mem.reported, .Relaxed) { return }
	for &s in store_mem.slots {
		m.cache += sync.atomic_load_explicit(&s[0], .Relaxed)
		m.schema += sync.atomic_load_explicit(&s[1], .Relaxed)
		m.stmt += sync.atomic_load_explicit(&s[2], .Relaxed)
	}
	return m, true
}

// ---- the newest backup ----------------------------------------------------------------
//
// platform/store/sqlite says when its newest backup was written (at open, from the files it
// finds, and after each one), and status shows its age, without either importing the other.

@(private)
backups: struct {
	ms: i64, // atomic: unix ms; 0: none yet
	on: bool, // atomic: a store here keeps backups (a file database)
}

backup_report :: proc "contextless" (unix_ms: i64) {
	sync.atomic_store_explicit(&backups.ms, unix_ms, .Relaxed)
	sync.atomic_store_explicit(&backups.on, true, .Relaxed)
}

// ok false: nothing here keeps backups. ms 0: none yet.
last_backup :: proc() -> (unix_ms: i64, ok: bool) {
	if !sync.atomic_load_explicit(&backups.on, .Relaxed) { return 0, false }
	return sync.atomic_load_explicit(&backups.ms, .Relaxed), true
}
