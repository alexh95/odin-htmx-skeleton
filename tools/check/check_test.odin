package main

import vmem "core:mem/virtual"
import "core:strings"
import "core:testing"

// One test, run in order: the checker keeps its state in package globals.
@(test)
checks :: proc(t: ^testing.T) {
	arena: vmem.Arena
	_ = vmem.arena_init_growing(&arena)
	defer vmem.arena_destroy(&arena)
	context.allocator = vmem.arena_allocator(&arena)

	// The repo itself: clean. (parity needs built binaries and both suites' runs,
	// so CI runs it after them, not here.)
	reset()
	tree := load(#directory + "/../..")
	check_imports(&tree)
	check_profiles(&tree)
	check_routes(&tree)
	check_contracts(&tree)
	testing.expectf(t, len(problems) == 0, "the tree has problems:\n%s", strings.join(problems[:], "\n"))

	// The bad fixture: every check trips on what it was written to catch.
	reset()
	bad := load(#directory + "/testdata/bad")
	check_imports(&bad)
	check_profiles(&bad)
	check_routes(&bad)
	check_contracts(&bad)
	check_parity(&bad)
	want := [?]string {
		// imports
		`features/x/models imports "../../../platform/web": models import core and platform L1–L2 only`,
		`features/x/web imports "../../y/web": a web package imports no other web package`,
		`features/x imports "../../platform/web": a domain returns plain values`,
		`features/x imports "store:y": a domain imports its own store`,
		`app/misc: not a package PLAN §5.1 places`,
		`app/platform/gizmo: a platform package with no layer`,
		`platform/obs imports "../web": L2 imports L3`,
		`stores/sqlite/x imports "../../../features/x": a store imports its models`,
		// profile
		`the "x" mount's row GET / is y's handler`,
		`build.sh names ghost, but there's no app/cmd/ghost`,
		`app/cmd/orphan has no line in build.sh`,
		`bad mounts features/x/web.ROUTES as "y"; it is x's`,
		`bad imports features/x/web, which declares init, but main never calls it`,
		`bad imports features/y/web, but no host mounts its ROUTES`,
		`bad imports features/y/web, which declares init, but main never calls it`,
		`migrate("y") runs x's migrations`,
		`bad reaches stores/sqlite/z, which has MIGRATIONS, but main never migrates "z"`,
		`features/y/web's ROUTES is mounted by no profile`,
		// routes
		`features/x/web.ROUTES holds a root row`,
		`the prefix /legacy has no reason`,
		`GET /elsewhere is outside x's prefixes`,
		`GET /shared is outside x's prefixes`,
		`the router key "/shared" is claimed by x and w`,
		`host main has 2 root rows`,
		`features/z declares ROUTES`,
		// contracts
		"app/stores/sqlite/x: no `_ : m.Store_Put : <proc>` line",
		"app/platform/authz/anonymous: an identity states",
		// parity
		`a route waiver without a reason: route | GET /x/y | load |`,
		`app/bin/bad isn't built`,
		`the waiver for GET /nowhere (e2e) is stale`,
	}
	for w in want {
		found := false
		for p in problems { found ||= strings.contains(p, w) }
		testing.expectf(t, found, "no problem says %q; got:\n%s", w, strings.join(problems[:], "\n"))
	}
	testing.expectf(t, len(problems) == len(want), "%d problems for %d expected:\n%s", len(problems), len(want), strings.join(problems[:], "\n"))
}

reset :: proc() {
	problems = {}
	profiles_cache = {}
	profiles_read = false
	readme_cache = {}
}

