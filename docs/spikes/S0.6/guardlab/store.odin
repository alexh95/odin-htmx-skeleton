package guardlab

// A WAL store in store v3's shape (PLAN §11.1): one writer connection behind a guard.Mutex, one
// read-only connection per event loop opened lazily. After a pure crash the loop's reader resets
// every statement (the pulled reset, §10.2 rule 3): the jump skipped the deferred resets, and a
// statement left mid-iteration holds its snapshot, which pins the WAL. The reset is pulled twice:
// before the reader's next use, and on the loop's 1 s tick, because a loop that gets no more reads
// would otherwise keep the snapshot for good (S0.6 found that case). `guard` never calls SQLite.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

import http "vendor_fork:odin-http"

import "guard"
import "sq"

Store :: struct {
	path:      string,
	wal:       string,
	writer:    sq.DB,
	writer_mu: guard.Mutex,
	insert:    sq.Stmt,
	no_reset:  bool,
}

store: Store

Reader :: struct {
	db:    sq.DB,
	iter:  sq.Stmt,
	count: sq.Stmt,
	boom:  sq.Stmt,
	seen:  u64,
	resets: int,
}

@(thread_local) tl_reader: Reader

// Per loop: crashes recovered, and whether its reader still has statements to reset (for /wal).
loop_crashes: [MAX_LOOPS]u64
loop_unreset: [MAX_LOOPS]bool

store_open :: proc(path: string) {
	store.path = path
	store.wal = strings.concatenate({path, "-wal"})
	store.no_reset = os.get_env("NO_RESET", context.temp_allocator) == "1"
	os.remove(path)
	os.remove(store.wal)
	os.remove(strings.concatenate({path, "-shm"}, context.temp_allocator))

	cpath := strings.clone_to_cstring(path)
	db, rc := sq.open(cpath, sq.OPEN_READWRITE | sq.OPEN_CREATE)
	assert(rc == sq.OK, "open")
	store.writer = db
	sq.exec(db, "PRAGMA journal_mode=WAL")
	sq.exec(db, "PRAGMA synchronous=NORMAL")
	sq.exec(db, "PRAGMA journal_size_limit=67108864")
	sq.exec(db, "PRAGMA busy_timeout=5000")
	sq.exec(db, "CREATE TABLE t (id INTEGER PRIMARY KEY, body TEXT NOT NULL)")
	sq.exec(db, "BEGIN")
	for i in 0 ..< 200 {
		sq.exec(db, fmt.ctprintf("INSERT INTO t(body) VALUES ('seed %d %s')", i, strings.repeat("x", 200, context.temp_allocator)))
	}
	sq.exec(db, "COMMIT")
	store.insert, _ = sq.prepare(db, "INSERT INTO t(body) VALUES (?)")
}

// The loop's reader; resets its statements first if this thread recovered from a crash since.
reader :: proc() -> ^Reader {
	r := &tl_reader
	if r.db == nil {
		db, rc := sq.open(strings.clone_to_cstring(store.path, context.temp_allocator), sq.OPEN_READONLY)
		assert(rc == sq.OK, "open reader")
		r.db = db
		sq.exec(db, "PRAGMA busy_timeout=5000")
		r.iter, _ = sq.prepare(db, "SELECT id FROM t ORDER BY id")
		r.count, _ = sq.prepare(db, "SELECT count(*) FROM t")
		sq.create_function(db, "boom", proc "c" (ctx: sq.Context, argc: i32, argv: [^]sq.Value) {
			// A trap inside SQLite's call stack: in_sqlite is up, so it's dirty.
			p := (^int)(uintptr(argc)) // argc is 0: a nil pointer the optimiser can't see
			p^ = 1
			sq.result_int(ctx, 0)
		})
		r.boom, _ = sq.prepare(db, "SELECT boom()")
		r.seen = guard.recoveries()
	}
	if r.seen != guard.recoveries() {
		r.seen = guard.recoveries()
		if !store.no_reset { r.resets += sq.reset_all(r.db) }
	}
	loop_unreset[tl_loop] = store.no_reset && r.seen != 0
	return r
}

// On the loop's 1 s tick: the same check, for a loop whose reader isn't used again.
store_reader_tick :: proc() {
	r := &tl_reader
	if r.db != nil && r.seen != guard.recoveries() { _ = reader() }
}

// POST /w: one row through the writer.
store_write :: proc(req: ^http.Request, res: ^http.Response) {
	guard.lock(&store.writer_mu)
	sq.bind_text(store.insert, 1, "a row written while the readers crash")
	rc := sq.step(store.insert)
	sq.reset(store.insert)
	guard.unlock(&store.writer_mu)
	if rc != sq.DONE {
		http.respond_plain(res, string(sq.errmsg(store.writer)), .Internal_Server_Error)
		return
	}
	http.respond(res, http.Status.No_Content)
}

// GET /r: a read on the loop's reader.
store_read :: proc(req: ^http.Request, res: ^http.Response) {
	r := reader()
	n: i64
	if sq.step(r.count) == sq.ROW { n = sq.column_int64(r.count, 0) }
	sq.reset(r.count)
	http.respond_plain(res, fmt.tprintf("%d", n))
}

// GET /wal: the WAL file's size in bytes.
store_wal :: proc(req: ^http.Request, res: ^http.Response) {
	n: i64 = -1
	if fi, err := os.stat(store.wal, context.temp_allocator); err == nil { n = fi.size }
	http.respond_plain(res, fmt.tprintf("%d resets=%d loop=%d crashes_per_loop=%v", n, tl_reader.resets, tl_loop, loop_crashes[:sync.atomic_load(&loops)]))
}
