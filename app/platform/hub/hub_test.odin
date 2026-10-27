package hub

import "core:strings"
import "core:testing"
import "core:thread"

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

// The map is keyed by the ring's own copy of the topic: the first message's copy goes once the
// ring lets that message go, and the next publish must still find the same ring (the soak's
// `free(): invalid pointer`, M2). The sweep then frees the idle rings and only those.
@(test)
rings_keep_their_own_topics :: proc(t: ^testing.T) {
	rings := make(map[string]^Ring)
	defer delete(rings)
	out: [dynamic]^Msg
	defer delete(out)
	first := strings.clone("lab.feed:a")
	r := ring_for(&rings, first, .Queue, 2, 1 << 20, 0, context.allocator)
	delete(first) // what releasing the first message did to the old key
	again := strings.clone("lab.feed:a")
	testing.expect(t, ring_for(&rings, again, .Queue, 2, 1 << 20, 0, context.allocator) == r)
	delete(again)
	testing.expect_value(t, len(rings), 1)

	b := ring_for(&rings, "lab.feed:b", .Queue, 2, 1 << 20, 0, context.allocator)
	c := ring_for(&rings, "lab.feed:c", .Queue, 2, 1 << 20, 0, context.allocator)
	r.last_ns, b.last_ns, c.last_ns = 0, 30, 100
	ring_add(b, msg(7, "b"), &out)
	floor, freed := ring_sweep(&rings, 100, 60, &out, context.allocator) // a and b idle for 60
	testing.expect_value(t, floor, 7)
	testing.expect_value(t, freed, 1)
	testing.expect_value(t, len(rings), 1)
	testing.expect(t, rings["lab.feed:c"] == c)
	expect_seqs(t, out[:], {7})
	for m in out { free(m) }
	clear(&out)
	_, _ = ring_sweep(&rings, 1000, 60, &out, context.allocator)
	testing.expect_value(t, len(rings), 0)

	// Made again after the sweep (floor 7), the ring vouches for no cursor below what the sweep let
	// go: one from before it resyncs instead of replaying across the gap (M2-04).
	again2 := ring_for(&rings, "lab.feed:b", .Queue, 2, 1 << 20, 7, context.allocator)
	testing.expect(t, !ring_covers(again2, 5))
	testing.expect(t, ring_covers(again2, 7))
	_, _ = ring_sweep(&rings, max(i64), 0, &out, context.allocator)
}

// Past the rings' total budget the one published to longest ago goes whole, never the one
// being published to, and the floor it reached comes back (M2-07).
@(test)
the_oldest_ring_goes_past_the_total_budget :: proc(t: ^testing.T) {
	rings := make(map[string]^Ring)
	defer delete(rings)
	out: [dynamic]^Msg
	defer delete(out)
	a := ring_for(&rings, "lab.feed:a", .Queue, 8, 1 << 20, 0, context.allocator)
	b := ring_for(&rings, "lab.feed:b", .Queue, 8, 1 << 20, 0, context.allocator)
	a.last_ns, b.last_ns = 10, 20
	ring_add(a, msg(3, "a", "xyz"), &out)
	ring_add(b, msg(4, "b", "xy"), &out)
	floor, freed, ok := ring_evict_oldest(&rings, b, &out, context.allocator)
	testing.expect(t, ok && floor == 3 && freed == 3)
	testing.expect(t, rings["lab.feed:a"] == nil && rings["lab.feed:b"] == b)
	_, _, ok = ring_evict_oldest(&rings, b, &out, context.allocator)
	testing.expect(t, !ok) // only the one being published to is left
	_, _ = ring_sweep(&rings, max(i64), 0, &out, context.allocator)
	for m in out { free(m) }
}

// Two publishers on two threads into one subscriber's inbox: it holds their messages in
// sequence order, so `deliver`, which skips what is at or below the newest it wrote, drops
// none of them (M2-02: appended after the hub mutex, they crossed and the lower one dropped).
@(test)
an_inbox_holds_two_publishers_in_sequence_order :: proc(t: ^testing.T) {
	N :: 2000
	h.rings = make(map[string]^Ring, heap())
	h.inboxes.allocator = heap()
	h.ring_cap, h.ring_bytes = 256, 1 << 20
	b := new(Inbox, heap())
	b.items.allocator, b.spare.allocator = heap(), heap()
	b.subs, b.armed = 1, true // armed: no drain is posted (there is no loop here)
	append(&h.inboxes, b)
	defer {
		for m in b.items { release(m) }
		delete(b.items)
		delete(b.spare)
		free(b, heap())
		out := make([dynamic]^Msg, heap())
		_, _ = ring_sweep(&h.rings, max(i64), 0, &out, heap())
		for m in out { release(m) }
		delete(out)
		delete(h.rings)
		delete(h.inboxes)
		h = {}
	}

	publish_n :: proc(topic: string) {
		for _ in 0 ..< N { post(new_msg(.Html, .Queue, topic, topic, "x"), 0) }
	}
	a := thread.create_and_start_with_poly_data("chat.room:1", publish_n)
	c := thread.create_and_start_with_poly_data("chat.typing:1", publish_n)
	thread.join_multiple(a, c)
	thread.destroy(a)
	thread.destroy(c)

	testing.expect_value(t, len(b.items), 2 * N)
	ordered := true
	for i in 1 ..< len(b.items) { ordered &&= b.items[i].seq > b.items[i - 1].seq }
	testing.expect(t, ordered)
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
