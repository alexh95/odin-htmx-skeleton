package store_memory

// ---- platform/store/memory: what the memory family's stores share (L2) ------------
//
// D16, D18. A memory store keeps its rows in the process, behind a guard.Mutex
// (the only lock the app takes, so a trap while it is held is dirty), and links no
// SQLite: a profile built with -collection:store=app/stores/memory builds where no
// SQLite library exists. Rows go when the process does; that is the family's
// contract, and its features say so on their pages.

import "core:sync"

import store ".."
import "../../guard"

Lock :: guard.Mutex
lock :: guard.lock
unlock :: guard.unlock

// Ids count from 1, as SQLite's rowids do, so views and routes can't tell the
// families apart.
Seq :: struct {
	last: i64,
}

next_id :: proc(s: ^Seq) -> i64 {
	return sync.atomic_add(&s.last, 1) + 1
}

// The memory family's writes are done when the store returns, so the caller's
// continuation runs at once, on its own loop, before the store call returns.
finish :: proc(op: ^store.Op) {
	op.done(op)
}

// A capped list, newest last: past `cap` the oldest row goes (a rolling buffer,
// §11.6). Not locked itself: the store holds its Lock around it.
Ring :: struct($T: typeid) {
	items: []T,
	head:  int, // index of the oldest
	n:     int,
}

ring_init :: proc(r: ^Ring($T), cap: int) {
	r.items = make([]T, cap)
}

// Appends `v`; returns the row it pushed out, if the ring was full.
ring_push :: proc(r: ^Ring($T), v: T) -> (dropped: T, did: bool) {
	if r.n < len(r.items) {
		r.items[(r.head + r.n) % len(r.items)] = v
		r.n += 1
		return
	}
	dropped = r.items[r.head]
	r.items[r.head] = v
	r.head = (r.head + 1) % len(r.items)
	return dropped, true
}

// The i-th row from the newest (0 = newest).
ring_newest :: proc(r: ^Ring($T), i: int) -> ^T {
	return &r.items[(r.head + r.n - 1 - i) % len(r.items)]
}

// Removes the rows `keep` refuses, in place, keeping the order.
ring_filter :: proc(r: ^Ring($T), keep: proc(v: ^T, data: rawptr) -> bool, data: rawptr) {
	out := 0
	for i in 0 ..< r.n {
		v := &r.items[(r.head + i) % len(r.items)]
		if keep(v, data) {
			r.items[(r.head + out) % len(r.items)] = v^
			out += 1
		}
	}
	r.n = out
}
