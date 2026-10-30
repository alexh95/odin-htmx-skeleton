package main

import "core:mem/virtual"
import "core:testing"

import "../../platform/app"

// The boot checks of §6.1 over this profile's tables, as `CMD=test build.sh full`
// runs them in CI: a table that would refuse to boot fails here first.
@(test)
boot_checks_pass :: proc(t: ^testing.T) {
	// What boot keeps for the process's life goes in an arena the test destroys, so
	// the runner's leak check sees none of it.
	arena: virtual.Arena
	_ = virtual.arena_init_growing(&arena)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator
	problems := app.dry_check(HOSTS[:], nil, BUNDLE_EXTS)
	for p in problems { testing.expectf(t, false, "%s", p) }
}
