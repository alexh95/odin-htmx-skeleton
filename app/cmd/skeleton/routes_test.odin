package main

import "core:testing"

import "../../platform/app"

// The boot checks of §6.1 over this profile's tables, as `CMD=test build.sh skeleton`
// runs them in CI: a table that would refuse to boot fails here first.
@(test)
boot_checks_pass :: proc(t: ^testing.T) {
	problems := app.dry_check(HOSTS[:], nil, BUNDLE_EXTS)
	for p in problems { testing.expectf(t, false, "%s", p) }
}
