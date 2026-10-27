package ops

import "core:testing"

// One test: the ring is the package's.
@(test)
a_minute_of_samples_with_their_rates :: proc(t: ^testing.T) {
	defer {
		delete(st.panel, heap())
		st = {}
	}
	defer free_all(context.temp_allocator)

	s, seq := record({at_ns = 1e9, requests = 100, published = 10})
	testing.expect_value(t, s.per_s, 0) // nothing to compare with yet
	testing.expect_value(t, seq, u64(1))
	s, _ = record({at_ns = 3e9, requests = 300, published = 50})
	testing.expect_value(t, s.per_s, 100) // 200 over 2 s
	testing.expect_value(t, s.published_per_s, 20)

	for i in 0 ..< HISTORY { _, _ = record({at_ns = i64(4 + i) * 1e9, requests = u64(400 + i)}) }
	all := make([dynamic]Sample, context.temp_allocator)
	newest := history(&all)
	testing.expect_value(t, len(all), HISTORY) // a minute, the oldest gone
	testing.expect_value(t, newest, u64(HISTORY + 2))
	testing.expect(t, all[0].at_ns < all[HISTORY - 1].at_ns)

	keep_panel("<p>one</p>", 5)
	keep_panel("<p>two</p>", 6)
	html, tag := panel()
	testing.expect_value(t, html, "<p>two</p>")
	testing.expect_value(t, tag, u64(6))
}
