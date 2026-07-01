package main

// ---- --minimal: strip the demo to a one-page starter --------------------
//
// Deletes the contacts/events demo (domain, pages, demo specs + load scenarios)
// and drops in a minimal but complete app: a single `Note` entity with a home
// page that lists notes and adds one over HTMX — the whole model → repository →
// service → view → controller stack, kept tiny so it reads as a template.
//
// The replacements live beside this file (tools/init/minimal/) as real files and
// are embedded at compile time (#load), so what lands in the project is exactly
// what you can read here.

import "core:fmt"
import "core:os"
import "core:strings"

MIN_MODELS :: #load("minimal/src/models/models.odin", string)
MIN_REPO :: #load("minimal/src/repository/repo.odin", string)
MIN_NOTES :: #load("minimal/src/repository/notes.odin", string)
MIN_MIGRATION :: #load("minimal/src/repository/migrations/0001_init.sql", string)
MIN_SERVICES :: #load("minimal/src/services/services.odin", string)
MIN_ROUTES :: #load("minimal/src/routes.odin", string)
MIN_CONTROLLERS :: #load("minimal/src/controllers/controllers.odin", string)
MIN_VIEWS :: #load("minimal/src/views/views.odin", string)
MIN_CSS :: #load("minimal/notes.css", string)
MIN_E2E :: #load("minimal/e2e/home.spec.ts", string)
MIN_PAGES :: #load("minimal/load/pages.js", string)

strip_to_minimal :: proc(opt: Options) {
	// 1. Delete the demo — domain + pages, and the specs/scenarios that cover them.
	demo := []string {
		"app/src/repository/contacts.odin",
		"app/src/repository/events.odin",
		"app/src/repository/migrations/0002_events.sql",
		"app/src/views/views_pages.odin",
		"app/src/views/views_fragments.odin",
		"e2e/tests/assets.spec.ts",
		"e2e/tests/components.spec.ts",
		"e2e/tests/crud.spec.ts",
		"e2e/tests/events.spec.ts",
		"e2e/tests/forms.spec.ts",
		"e2e/tests/navigation.spec.ts",
		"e2e/tests/persistence.spec.ts",
		"e2e/tests/responsive.spec.ts",
		"e2e/tests/search.spec.ts",
		"load-tests/scenarios/api.js",
		"load-tests/scenarios/detail.js",
		"load-tests/scenarios/list.js",
		"load-tests/scenarios/mixed.js",
		"load-tests/scenarios/search.js",
		"load-tests/scenarios/write.js",
	}
	for f in demo {
		remove_file(f)
	}

	// 2. Drop in the minimal app (overwrites the demo's core files; main.odin,
	//    sqlite/, brand.odin, app.css/js are kept as-is).
	put("app/src/models/models.odin", MIN_MODELS)
	put("app/src/repository/repo.odin", MIN_REPO)
	put("app/src/repository/notes.odin", MIN_NOTES)
	put("app/src/repository/migrations/0001_init.sql", MIN_MIGRATION)
	put("app/src/services/services.odin", MIN_SERVICES)
	put("app/src/routes.odin", MIN_ROUTES)
	put("app/src/controllers/controllers.odin", MIN_CONTROLLERS)
	put("app/src/views/views.odin", MIN_VIEWS)
	put("e2e/tests/home.spec.ts", MIN_E2E)
	put("load-tests/scenarios/pages.js", MIN_PAGES)

	// 3. The note-page styles ride on top of the kept theme/component CSS.
	append_file("app/static/app.css", MIN_CSS)

	// 4. Point the load driver at the surviving scenarios.
	edit(
		"load-tests/run.sh",
		[]Repl {
			{`SCENARIOS="static pages list search api detail write mixed"`, `SCENARIOS="static pages"`},
			{`for path in /static/app.css /api/search?q=a /; do`, `for path in /static/app.css /; do`},
		},
	)
}

@(private = "file")
put :: proc(path, content: string) {
	if werr := os.write_entire_file(path, content); werr != nil {
		fmt.eprintfln("  ERROR writing %s: %v", path, werr)
		os.exit(1)
	}
	fmt.printfln("  wrote    %s", path)
}

@(private = "file")
remove_file :: proc(path: string) {
	if err := os.remove(path); err != nil {
		fmt.printfln("  (absent) %s", path)
	} else {
		fmt.printfln("  removed  %s", path)
	}
}

@(private = "file")
append_file :: proc(path, extra: string) {
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		fmt.eprintfln("  ERROR reading %s: %v", path, rerr)
		os.exit(1)
	}
	if werr := os.write_entire_file(path, strings.concatenate({string(data), extra})); werr != nil {
		fmt.eprintfln("  ERROR writing %s: %v", path, werr)
		os.exit(1)
	}
	fmt.printfln("  appended %s", path)
}
