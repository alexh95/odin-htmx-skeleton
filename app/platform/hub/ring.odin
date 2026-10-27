package hub

// ---- a topic's replay ring, and its policy ----------------------------------------
//
// Pure bookkeeping under the hub mutex, apart from the sockets (unit-tested).
// Each topic keeps its newest messages for a reconnect to replay (§9.3):
//
//   .Queue   the last `cap` messages, in order; anything older is `dropped`, and a
//            cursor below it can't be served from the ring;
//   .Latest  the newest message per publish key, at most `cap` keys: replay gives
//            each key's latest (presence, counters, progress rows);
//   .Sample  only the newest message: telemetry, where a missed one is never owed.

import "base:runtime"
import "core:strings"

Policy :: enum u8 {
	Queue,
	Latest,
	Sample,
}

Ring :: struct {
	topic:   string, // its own copy: the rings map's key, never a message's topic, which goes with it
	policy:  Policy,
	cap:     int,
	max:     int, // bytes held at most (HUB_RING_BYTES)
	msgs:    [dynamic]^Msg, // oldest first
	bytes:   int,
	dropped: u64, // the newest seq evicted while still owed: a cursor below it missed it
	last_ns: i64, // the last publish, for the idle sweep
}

// The topic's ring, made on its first publish. The map is keyed by the ring's own copy of the
// topic: keyed by the first message's (as it was), the key dangled once that message left the
// ring, and a lookup compared against freed memory (the soak's `free(): invalid pointer`). A new
// ring vouches for nothing at or below `floor`, the newest seq the idle sweep let go: made again
// after a sweep, it would otherwise cover a cursor from before it, and the gap went unseen (M2-04).
ring_for :: proc(rings: ^map[string]^Ring, topic: string, policy: Policy, cap, max: int, floor: u64, allocator: runtime.Allocator) -> ^Ring {
	if r := rings[topic]; r != nil { return r }
	r := new(Ring, allocator)
	r.topic = strings.clone(topic, allocator)
	r.policy, r.cap, r.max, r.dropped = policy, cap, max, floor
	r.msgs.allocator = allocator
	rings[r.topic] = r
	return r
}

// Rings with no publish for `ttl` let their messages go (into `out`, for the caller to release)
// and are freed; returns the newest seq they reached and the bytes they held. Collected first,
// then deleted: a map doesn't keep its iteration across a delete.
ring_sweep :: proc(rings: ^map[string]^Ring, now, ttl: i64, out: ^[dynamic]^Msg, allocator: runtime.Allocator) -> (floor: u64, freed: int) {
	idle := make([dynamic]^Ring, context.temp_allocator)
	for _, r in rings {
		if now - r.last_ns >= ttl { append(&idle, r) }
	}
	for r in idle {
		f, b := ring_drop(rings, r, out, allocator)
		floor, freed = max(floor, f), freed + b
	}
	return
}

// The ring published to longest ago, other than `keep`, goes whole, as the sweep would take
// it: what the rings' total budget does past HUB_RINGS_BYTES (M2-07). false: none to take.
ring_evict_oldest :: proc(rings: ^map[string]^Ring, keep: ^Ring, out: ^[dynamic]^Msg, allocator: runtime.Allocator) -> (floor: u64, freed: int, ok: bool) {
	oldest: ^Ring
	for _, r in rings {
		if r != keep && (oldest == nil || r.last_ns < oldest.last_ns) { oldest = r }
	}
	if oldest == nil { return }
	floor, freed = ring_drop(rings, oldest, out, allocator)
	return floor, freed, true
}

// Lets a ring's messages go and frees it: the newest seq it reached, and the bytes it held.
@(private)
ring_drop :: proc(rings: ^map[string]^Ring, r: ^Ring, out: ^[dynamic]^Msg, allocator: runtime.Allocator) -> (floor: u64, freed: int) {
	for m in r.msgs { floor = max(floor, m.seq) }
	floor = max(floor, r.dropped)
	freed = r.bytes
	ring_empty(r, out)
	delete_key(rings, r.topic)
	delete(r.msgs)
	delete(r.topic, allocator)
	free(r, allocator)
	return
}

// Adds `m`, taking the ring's reference to it. What it pushes out is appended
// to `out`, for the caller to release after the hub mutex.
ring_add :: proc(r: ^Ring, m: ^Msg, out: ^[dynamic]^Msg) {
	switch r.policy {
	case .Queue:
	case .Latest:
		// A newer message for the same key supersedes the old one: nothing is owed.
		for old, i in r.msgs {
			if old.key == m.key {
				ordered_remove(&r.msgs, i)
				r.bytes -= len(old.html)
				append(out, old)
				break
			}
		}
	case .Sample:
		for old in r.msgs { append(out, old) }
		clear(&r.msgs)
		r.bytes = 0
	}
	append(&r.msgs, m)
	r.bytes += len(m.html)
	for len(r.msgs) > 1 && (len(r.msgs) > r.cap || r.bytes > r.max) {
		old := r.msgs[0]
		ordered_remove(&r.msgs, 0)
		r.bytes -= len(old.html)
		r.dropped = max(r.dropped, old.seq)
		append(out, old)
	}
}

// Whether a cursor at `from` missed nothing this ring has let go of.
ring_covers :: proc(r: ^Ring, from: u64) -> bool {
	return r.policy == .Sample || from >= r.dropped
}

// The ring's messages after `from`, oldest first (each key's latest for .Latest).
ring_after :: proc(r: ^Ring, from: u64, out: ^[dynamic]^Msg) {
	for m in r.msgs {
		if m.seq > from { append(out, m) }
	}
}

// Everything the ring holds, for the idle sweep; the ring is left empty.
ring_empty :: proc(r: ^Ring, out: ^[dynamic]^Msg) {
	for m in r.msgs { append(out, m) }
	clear(&r.msgs)
	r.bytes = 0
}

// ---- cursors and topic names -------------------------------------------------------

// `<epoch>-<seq>`: ours when the epoch is this process's.
parse_cursor :: proc(s: string, epoch: u64) -> (seq: u64, ours: bool) {
	dash := -1
	for c, i in s {
		if c == '-' { dash = i; break }
	}
	if dash <= 0 { return }
	e, e_ok := parse_u64(s[:dash])
	n, n_ok := parse_u64(s[dash + 1:])
	if !e_ok || !n_ok || e != epoch { return }
	return n, true
}

// Digits only, no sign, no separators, no overflow.
parse_u64 :: proc(s: string) -> (n: u64, ok: bool) {
	if len(s) == 0 || len(s) > 20 { return }
	for c in transmute([]byte)s {
		if c < '0' || c > '9' { return }
		d := u64(c - '0')
		if n > (max(u64) - d) / 10 { return }
		n = n * 10 + d
	}
	return n, true
}

// "chat.room:12" → family "chat.room", key "12"; "ops.panel" → "ops.panel", "".
split_topic :: proc(topic: string) -> (family, key: string) {
	for c, i in topic {
		if c == ':' { return topic[:i], topic[i + 1:] }
	}
	return topic, ""
}

// One entry of `/events?t=`: a topic, with `@<rowid>` for a persisted one (the
// newest rowid the page rendered, D13). Names are `<feature>.<family>[:<key>]`
// in [a-z0-9_.:-], at most 128 bytes.
Wanted :: struct {
	topic:     string,
	rowid:     i64,
	has_rowid: bool,
}

parse_wanted :: proc(entry: string) -> (w: Wanted, ok: bool) {
	name := entry
	for c, i in entry {
		if c == '@' {
			name = entry[:i]
			n, nok := parse_u64(entry[i + 1:])
			if !nok || n > u64(max(i64)) { return }
			w.rowid, w.has_rowid = i64(n), true
			break
		}
	}
	if len(name) == 0 || len(name) > 128 { return }
	for c in transmute([]byte)name {
		switch c {
		case 'a' ..= 'z', '0' ..= '9', '_', '.', ':', '-':
		case:
			return
		}
	}
	w.topic = name
	return w, true
}
