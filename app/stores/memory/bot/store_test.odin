package bot_store_memory

import "core:testing"

import "../../../platform/store"
import m "../../../features/bot/models"

@(private = "file")
open_conv :: proc(owner: u64) -> i64 {
	op := store.new_op(m.Start, 64)
	op.owner, op.title = owner, "New conversation"
	op.done = proc(o: ^store.Op) {}
	_ = start(op)
	id := op.result.id
	store.free_op(op)
	return id
}

@(private = "file")
say :: proc(owner: u64, conv: i64, text: string, title := "") -> m.Error {
	op := store.new_op(m.Append, 2 * len(text) + len(title))
	op.owner, op.turn, op.title = owner, m.Turn{conv = conv, role = .User, text = text}, title
	op.done = proc(o: ^store.Op) {}
	_ = append_turn(op)
	err := op.err
	store.free_op(op)
	return err
}

@(private = "file")
reset :: proc() {
	for _, r in s.owners {
		for i in 0 ..< r.n { forget(r.items[(r.head + i) % len(r.items)]) }
		delete(r.items)
		free(r)
	}
	delete(s.owners)
	s = {}
}

// One test: the store is the package's.
@(test)
a_conversation_is_its_owners_alone :: proc(t: ^testing.T) {
	defer reset()
	defer free_all(context.temp_allocator)
	c := open_conv(7)
	testing.expect_value(t, say(7, c, "hello", "hello"), m.Error.None)
	testing.expect_value(t, say(8, c, "not mine"), m.Error.Not_Found) // someone else's
	got, err := conversation(7, c)
	testing.expect_value(t, err, m.Error.None)
	testing.expect_value(t, got.title, "hello")
	testing.expect_value(t, got.turns, 1)
	_, err = conversation(8, c)
	testing.expect_value(t, err, m.Error.Not_Found)

	for _ in 0 ..< TURNS + 3 { _ = say(7, c, "more") }
	ts := make([dynamic]m.Turn, context.temp_allocator)
	testing.expect_value(t, turns(7, c, &ts), m.Error.None)
	testing.expect_value(t, len(ts), TURNS) // the oldest went
	testing.expect(t, ts[0].id < ts[len(ts) - 1].id) // oldest first

	for _ in 0 ..< KEEP { _ = open_conv(7) }
	cs := make([dynamic]m.Conversation, context.temp_allocator)
	_ = conversations(7, 1000, &cs)
	testing.expect_value(t, len(cs), KEEP)
	_, err = conversation(7, c) // the first went with the 51st
	testing.expect_value(t, err, m.Error.Not_Found)

	// At most MAX_OWNERS members' conversations: past it a new member's first pushes out
	// another member's (M2-06).
	for owner in 0 ..< MAX_OWNERS + 4 { _ = open_conv(u64(100 + owner)) }
	testing.expect_value(t, len(s.owners), MAX_OWNERS)
	last := open_conv(u64(100 + MAX_OWNERS + 3))
	_, err = conversation(u64(100 + MAX_OWNERS + 3), last)
	testing.expect_value(t, err, m.Error.None)
}
