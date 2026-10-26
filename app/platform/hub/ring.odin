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

Policy :: enum u8 {
	Queue,
	Latest,
	Sample,
}

Ring :: struct {
	policy:  Policy,
	cap:     int,
	max:     int, // bytes held at most (HUB_RING_BYTES)
	msgs:    [dynamic]^Msg, // oldest first
	bytes:   int,
	dropped: u64, // the newest seq evicted while still owed: a cursor below it missed it
	last_ns: i64, // the last publish, for the idle sweep
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
