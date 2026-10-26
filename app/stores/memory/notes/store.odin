package notes_store_memory

// ---- notes in memory ----------------------------------------------------------------------
//
// The newest notes in a ring behind the store's lock; they go when the process
// does. A note's text is copied into the heap when it is added and freed when the
// ring pushes it out, so what a reader gets is a copy into its request arena.

import "core:strings"
import "core:time"

import "../../../platform/store"
import mem_store "../../../platform/store/memory"
import m "../../../features/notes/models"

IMPL :: "memory"

// More than any page shows; the oldest go first.
KEEP :: 500

@(private)
s: struct {
	lock:  mem_store.Lock,
	ring:  mem_store.Ring(m.Note),
	seq:   mem_store.Seq,
	ready: bool,
}

@(private)
init_once :: proc() {
	if s.ready { return }
	s.ready = true
	mem_store.ring_init(&s.ring, KEEP)
}

recent :: proc(limit: int, out: ^[dynamic]m.Note) -> m.Error {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	init_once()
	for i in 0 ..< min(limit, s.ring.n) {
		n := mem_store.ring_newest(&s.ring, i)^
		n.body = strings.clone(n.body, context.temp_allocator)
		append(out, n)
	}
	return .None
}

// Stored at once, so the caller's continuation runs before this returns.
add :: proc(op: ^m.Add) -> bool {
	mem_store.lock(&s.lock)
	init_once()
	n := m.Note{id = mem_store.next_id(&s.seq), body = strings.clone(op.body), at = time.time_to_unix(time.now())}
	if old, dropped := mem_store.ring_push(&s.ring, n); dropped { delete(old.body) }
	mem_store.unlock(&s.lock)
	op.result = n
	op.result.body = strings.clone(n.body, store.op_allocator(op))
	op.err = .None
	mem_store.finish(op)
	return true
}

// The starter's three sample notes, oldest first an hour apart, so ids and times
// agree and the welcome note tops the list. Into an empty store only.
seed :: proc() {
	mem_store.lock(&s.lock)
	defer mem_store.unlock(&s.lock)
	init_once()
	if s.ring.n > 0 { return }
	now := time.time_to_unix(time.now())
	for body, i in SAMPLES {
		mem_store.ring_push(&s.ring, m.Note{id = mem_store.next_id(&s.seq), body = strings.clone(body), at = now - i64(len(SAMPLES) - 1 - i) * 3600})
	}
}

SAMPLES := [?]string {
	"Notes live in a store: app/stores/memory/notes here, app/stores/sqlite/notes in a SQLite build.",
	"Build your thing in app/features: a feature is its models, domain, views and web packages.",
	"Welcome — this is your minimal starter.",
}
