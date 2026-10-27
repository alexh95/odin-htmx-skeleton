package store_memory

import "core:testing"

@(test)
ring_keeps_the_newest :: proc(t: ^testing.T) {
	r: Ring(int)
	ring_init(&r, 3)
	defer delete(r.items)
	for v in 1 ..= 3 {
		_, dropped := ring_push(&r, v)
		testing.expect(t, !dropped)
	}
	old, dropped := ring_push(&r, 4)
	testing.expect(t, dropped && old == 1)
	testing.expect_value(t, ring_newest(&r, 0)^, 4)
	testing.expect_value(t, ring_newest(&r, 2)^, 2)
	ring_filter(&r, proc(v: ^int, _: rawptr) -> bool { return v^ != 3 }, nil)
	testing.expect_value(t, r.n, 2)
	testing.expect_value(t, ring_newest(&r, 0)^, 4)
	testing.expect_value(t, ring_newest(&r, 1)^, 2)

	s: Seq
	testing.expect_value(t, next_id(&s), 1)
	testing.expect_value(t, next_id(&s), 2)
}

// A ring grows as it fills, in order even when its oldest moved (chat's byte budget takes it
// from the front), and holds at most its cap.
@(test)
ring_grows_to_its_cap :: proc(t: ^testing.T) {
	r: Ring(int)
	ring_init(&r, 20)
	defer delete(r.items)
	testing.expect_value(t, len(r.items), 8)
	for v in 1 ..= 8 { _, _ = ring_push(&r, v) }
	r.head, r.n = 1, 7 // the oldest (1) taken from the front
	_, _ = ring_push(&r, 9) // wraps into slot 0
	_, _ = ring_push(&r, 10) // full at 8: grows, the oldest first
	testing.expect_value(t, len(r.items), 16)
	for i in 0 ..< r.n { testing.expect_value(t, ring_newest(&r, i)^, 10 - i) }
	for v in 11 ..= 30 { _, _ = ring_push(&r, v) }
	testing.expect_value(t, len(r.items), 20)
	testing.expect_value(t, r.n, 20)
	testing.expect_value(t, ring_newest(&r, 0)^, 30)
	testing.expect_value(t, ring_newest(&r, 19)^, 11)
}
