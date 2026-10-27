package main

import "core:mem/virtual"
import "core:testing"

import "../../platform/app"
import "../../platform/html"

// The boot checks of §6.1 over this profile's tables, as `CMD=test build.sh lab`
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
	problems := app.dry_check(HOSTS[:], JOBS[:], BUNDLE_EXTS, PAGE_BUNDLES)
	for p in problems { testing.expectf(t, false, "%s", p) }
}

// The lab is on the hyperscript client: html.behave writes a lone install, the
// only `_` the gate in app.js initialises, for twinned and hyperscript-only
// behaviours alike.
@(test)
behave_writes_installs :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, html.behave_attr(.Tabs), ` _="install Tabs"`)
	testing.expect_value(t, html.behave_attr(.Reset_On_Success), ` _="install ResetOnSuccess"`)
	testing.expect_value(t, html.behave_attr(.Copy_Text), ` _="install CopyText"`)
}
