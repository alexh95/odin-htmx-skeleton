package notify_store_memory

import "core:strings"
import "core:testing"
import "core:time"

import "../../../platform/store"
import m "../../../features/notify/models"

@(private = "file")
Probe :: struct {
	using add: m.Add,
	got:       ^m.Item,
	count:     ^int,
}

@(private = "file")
send :: proc(user: u64, html: string, got: ^m.Item = nil, count: ^int = nil) {
	op := store.new_op(Probe, 64)
	op.user, op.kind, op.ref, op.html = user, "test.ping", "/x", html
	op.got, op.count = got, count
	op.done = proc(o: ^store.Op) {
		p := (^Probe)(o)
		if p.got != nil {
			p.got^ = p.result
			p.got.html = strings.clone(p.result.html, context.temp_allocator) // the op's arena goes below
		}
		if p.count != nil { p.count^ = p.add.unread }
		store.free_op(p)
	}
	_ = add(op)
}

@(private = "file")
reset :: proc() {
	for _, r in s.users {
		for i in 0 ..< r.n { free_item(r.items[(r.head + i) % len(r.items)]) }
		delete(r.items)
		free(r)
	}
	delete(s.users)
	s.users = nil
}

// One test: the store is the package's.
@(test)
a_member_keeps_their_newest :: proc(t: ^testing.T) {
	defer reset()
	defer free_all(context.temp_allocator)
	got: m.Item
	count: int
	send(7, "first", &got, &count)
	testing.expect_value(t, count, 1)
	testing.expect_value(t, got.html, "first")
	testing.expect(t, got.id > 0)
	for _ in 0 ..< KEEP + 5 { send(7, "more") }
	send(8, "someone else's")
	list_of :: proc(user: u64) -> [dynamic]m.Item {
		out := make([dynamic]m.Item, context.temp_allocator)
		_ = list(user, 1000, &out)
		return out
	}
	testing.expect_value(t, len(list_of(7)), KEEP) // the oldest went
	testing.expect_value(t, unread(7), KEEP)
	testing.expect_value(t, len(list_of(8)), 1)
	testing.expect_value(t, len(list_of(9)), 0)

	testing.expect_value(t, mark_read(7), m.Error.None)
	testing.expect_value(t, unread(7), 0)
	testing.expect_value(t, unread(8), 1)

	// Read ones older than the cut go; unread ones stay whatever their age.
	future := time.time_to_unix(time.now()) + 10
	testing.expect_value(t, prune(future), KEEP)
	testing.expect_value(t, len(list_of(7)), 0)
	testing.expect_value(t, len(list_of(8)), 1)
}
