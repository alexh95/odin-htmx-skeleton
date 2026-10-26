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
