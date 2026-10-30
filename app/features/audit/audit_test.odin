package audit

import "core:strings"
import "core:testing"
import "core:unicode/utf8"

// A filter longer than the log's longest value is cut by rune, never inside one (M4-15).
@(test)
a_long_filter_is_cut_by_rune :: proc(t: ^testing.T) {
	long := strings.concatenate({strings.repeat("a", MAX_FILTER - 1, context.temp_allocator), "é", "zz"}, context.temp_allocator)
	f := filter(long, "  accounts.reset  ", 0)
	testing.expect_value(t, f.actor, long[:MAX_FILTER - 1])
	testing.expect(t, utf8.valid_string(f.actor))
	testing.expect_value(t, f.action, "accounts.reset")
	free_all(context.temp_allocator)
}
