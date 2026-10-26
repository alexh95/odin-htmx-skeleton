package hub

import "core:testing"

@(private = "file")
msg :: proc(seq: u64, key: string, html := "x") -> ^Msg {
	m := new(Msg)
	m.seq, m.key, m.html = seq, key, html
	return m
}

@(private = "file")
seqs :: proc(ms: []^Msg) -> []u64 {
	out := make([]u64, len(ms), context.temp_allocator)
	for m, i in ms { out[i] = m.seq }
	return out
}

@(private = "file")
expect_seqs :: proc(t: ^testing.T, got: []^Msg, want: []u64, loc := #caller_location) {
	s := seqs(got)
	ok := len(s) == len(want)
	for i in 0 ..< min(len(s), len(want)) { ok = ok && s[i] == want[i] }
	testing.expectf(t, ok, "seqs %v, want %v", s, want, loc = loc)
}

@(private = "file")
free_all_msgs :: proc(r: ^Ring, out: ^[dynamic]^Msg) {
	ring_empty(r, out)
	for m in out { free(m) }
	delete(out^)
	delete(r.msgs)
}

@(test)
queue_ring_keeps_the_last_and_marks_what_it_dropped :: proc(t: ^testing.T) {
	r := Ring{policy = .Queue, cap = 3, max = 1 << 20}
	out: [dynamic]^Msg
	for seq in u64(1) ..= 5 { ring_add(&r, msg(seq, "room"), &out) }
	expect_seqs(t, r.msgs[:], {3, 4, 5})
	expect_seqs(t, out[:], {1, 2})
	testing.expect_value(t, r.dropped, 2)
	testing.expect(t, !ring_covers(&r, 1)) // a cursor at 1 missed 2
	testing.expect(t, ring_covers(&r, 2))

	after := make([dynamic]^Msg, context.temp_allocator)
	ring_after(&r, 3, &after)
	expect_seqs(t, after[:], {4, 5})
	free_all_msgs(&r, &out)
}

@(test)
queue_ring_holds_its_bytes_but_keeps_the_newest :: proc(t: ^testing.T) {
	r := Ring{policy = .Queue, cap = 100, max = 10}
	out: [dynamic]^Msg
	ring_add(&r, msg(1, "a", "12345"), &out)
	ring_add(&r, msg(2, "a", "12345"), &out)
	ring_add(&r, msg(3, "a", "123"), &out) // 13 bytes: 1 goes
	expect_seqs(t, r.msgs[:], {2, 3})
	ring_add(&r, msg(4, "a", "0123456789abcdef"), &out) // larger than the cap alone: kept
	expect_seqs(t, r.msgs[:], {4})
	testing.expect_value(t, r.dropped, 3)
	free_all_msgs(&r, &out)
}

@(test)
latest_ring_keeps_each_keys_newest :: proc(t: ^testing.T) {
	r := Ring{policy = .Latest, cap = 2, max = 1 << 20}
	out: [dynamic]^Msg
	ring_add(&r, msg(1, "run-1"), &out)
	ring_add(&r, msg(2, "run-2"), &out)
	ring_add(&r, msg(3, "run-1"), &out) // supersedes 1: nothing owed
	expect_seqs(t, r.msgs[:], {2, 3})
	testing.expect_value(t, r.dropped, 0)
	testing.expect(t, ring_covers(&r, 0))
	ring_add(&r, msg(4, "run-3"), &out) // a third key past cap 2: run-2's state is lost
	expect_seqs(t, r.msgs[:], {3, 4})
	testing.expect_value(t, r.dropped, 2)
	free_all_msgs(&r, &out)
}

@(test)
sample_ring_keeps_one_and_owes_nothing :: proc(t: ^testing.T) {
	r := Ring{policy = .Sample, cap = 256, max = 1 << 20}
	out: [dynamic]^Msg
	for seq in u64(1) ..= 4 { ring_add(&r, msg(seq, "ops.panel"), &out) }
	expect_seqs(t, r.msgs[:], {4})
	testing.expect(t, ring_covers(&r, 0))
	after := make([dynamic]^Msg, context.temp_allocator)
	ring_after(&r, 0, &after)
	expect_seqs(t, after[:], {4})
	free_all_msgs(&r, &out)
}

@(test)
cursors_are_ours_only_from_this_epoch :: proc(t: ^testing.T) {
	seq, ours := parse_cursor("1761500000123-42", 1761500000123)
	testing.expect(t, ours && seq == 42)
	for bad in ([?]string{"1761500000124-42", "", "-42", "1761500000123-", "1761500000123", "x-1", "1761500000123-+1", "1761500000123-99999999999999999999999"}) {
		_, ours = parse_cursor(bad, 1761500000123)
		testing.expectf(t, !ours, "%q read as ours", bad)
	}
}

@(test)
wanted_topics_parse_strictly :: proc(t: ^testing.T) {
	w, ok := parse_wanted("chat.room:12@88200")
	testing.expect(t, ok && w.topic == "chat.room:12" && w.has_rowid && w.rowid == 88200)
	w, ok = parse_wanted("ops.panel")
	testing.expect(t, ok && w.topic == "ops.panel" && !w.has_rowid)
	for bad in ([?]string{"", "Chat.room", "chat room", "chat.room:12@", "chat.room:12@-1", "chat.room:12@x", "a<b", "@5"}) {
		_, ok = parse_wanted(bad)
		testing.expectf(t, !ok, "%q parsed", bad)
	}
	family, key := split_topic("notify.user:42")
	testing.expect(t, family == "notify.user" && key == "42")
	family, key = split_topic("home.presence")
	testing.expect(t, family == "home.presence" && key == "")
}
