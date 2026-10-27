package chat

import "core:testing"

@(private = "file")
reset :: proc() {
	for _, name in st.names { delete(name, heap()) }
	delete(st.names)
	for _, r in st.read { delete(r) }
	delete(st.read)
	for _, &r in st.here {
		for _, p in r { delete(p.name, heap()) }
		delete(r)
	}
	delete(st.here)
	st = {}
}

// One test: the domain's state is the package's.
@(test)
the_room_knows_who_is_there :: proc(t: ^testing.T) {
	defer reset()
	defer free_all(context.temp_allocator)

	// Presence: nothing, then online once however many streams, away after the last.
	here := make([dynamic]Presence_Change, context.temp_allocator)
	present(1, &here)
	testing.expect_value(t, len(here), 0)
	c, show := join(1, 7, "ann")
	testing.expect(t, show)
	testing.expect_value(t, c.state, Presence_State.Online)
	_, show = join(1, 7, "ann")
	testing.expect(t, !show)
	leave(1, 7)
	leave(1, 7)
	present(1, &here)
	testing.expect_value(t, len(here), 1)
	changes := make([dynamic]Presence_Change, context.temp_allocator)
	sweep_presence(&changes) // inside the debounce: still online
	testing.expect_value(t, len(changes), 0)

	// Mentions: by the name a member last used, without case, never the author.
	seen(7, "ann")
	seen(8, "Bob")
	seen(8, "bob.b")
	who := make([dynamic]u64, context.temp_allocator)
	mentioned("hi @BOB.B and @ann, and @nobody.", 7, &who)
	testing.expect_value(t, len(who), 1)
	if len(who) == 1 { testing.expect_value(t, who[0], u64(8)) }

	// Read cursors only move forward.
	testing.expect(t, mark_read(1, 7, 10))
	testing.expect(t, !mark_read(1, 7, 9))
	readers_of := make([dynamic]u64, context.temp_allocator)
	readers(1, &readers_of)
	testing.expect_value(t, len(readers_of), 1)

	// Room names and slugs.
	name, slug, problem := check_room("  Off Topic!  ")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, name, "Off Topic!")
	testing.expect_value(t, slug, "off-topic")
	_, _, problem = check_room("!!!")
	testing.expect(t, problem != "")
}
