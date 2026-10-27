package guard

// ---- drills: the crash kinds a TEST_ROUTES build answers (PLAN §19.1.10) ----------------
//
// `-define:TEST_ROUTES=true` mounts /__test/crash/<kind> (platform/web), which
// runs the kind inside a request, so the guard meets a real crash of each class.
// The platform's kinds are web's own; a package that can crash where web can't
// reach registers its kind here at boot: store/sqlite's `sqlite`, a trap inside
// a call into SQLite. A release build mounts nothing and registers nothing: the
// route answers 404 (D10).

TEST_ROUTES :: #config(TEST_ROUTES, false)

Drill :: struct {
	kind:   string,
	run:    proc(),
	handle: proc(req, res: rawptr), // a kind that answers the request itself (a socket's): web's Request and Response
}

drills: [dynamic]Drill

register_drill :: proc(kind: string, run: proc()) {
	when TEST_ROUTES { append(&drills, Drill{kind = kind, run = run}) }
}

// A kind that takes the request over: platform/stream's `wsdata` upgrades it to
// a socket, whose on_data crashes. guard is below web, so the request and the
// response travel as pointers.
register_drill_handler :: proc(kind: string, handle: proc(req, res: rawptr)) {
	when TEST_ROUTES { append(&drills, Drill{kind = kind, handle = handle}) }
}
