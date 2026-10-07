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
MIN_E2E_ABOUT :: #load("minimal/e2e/about.spec.ts", string)
MIN_PAGES :: #load("minimal/load/pages.js", string)
MIN_NOTES_LOAD :: #load("minimal/load/notes.js", string)
MIN_CHANGELOG :: #load("minimal/CHANGELOG.md", string)
MIN_TODO :: #load("minimal/TODO.md", string)

// The local dev database app/run.* default to. It holds the demo's tables at
// the demo's migration count, so the starter's migration runner would count
// them as applied and boot into "no such table: notes". It's disposable: the
// next run creates and seeds a fresh one.
DEV_DB :: [?]string{"app/data.db", "app/data.db-wal", "app/data.db-shm"}

// The tail of ci.yml's "Smoke test the binary" step, and what it becomes: the
// starter's read and write paths in place of the demo's.
SMOKE_DEMO :: `code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:8099/api/search?q=a")
          test "$code" = "200" || { echo "api/search returned $code"; exit 1; }
          curl -fsS -X POST "http://127.0.0.1:8099/contacts" \
            --data 'name=CI Smoke&email=ci@example.com&role=0&status=1' -o /dev/null`
SMOKE_MINIMAL :: `curl -fsS "http://127.0.0.1:8099/about"                     -o /dev/null
          curl -fsS -X POST "http://127.0.0.1:8099/notes" --data 'body=CI+smoke' -o /dev/null`

strip_to_minimal :: proc(opt: Options) {
	for f in DEV_DB {
		remove_if_present(f)
	}

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
		remove(f)
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
	put("e2e/tests/about.spec.ts", MIN_E2E_ABOUT)
	put("load-tests/scenarios/pages.js", MIN_PAGES)
	put("load-tests/scenarios/notes.js", MIN_NOTES_LOAD)

	// 3. The note-page styles ride on top of the kept theme/component CSS.
	append_to("app/static/app.css", MIN_CSS)

	// 4. The load driver runs whatever scenarios are left; only its optional
	//    bombardier baseline names a demo path. CI's build-job smoke test hits
	//    two demo routes the starter doesn't have, so it gets the starter's.
	edit(
		"load-tests/run.sh",
		[]Repl {
			{`for path in /static/app.css /api/search?q=a /; do`, `for path in /static/app.css /; do`},
		},
	)
	edit(".github/workflows/ci.yml", []Repl{{SMOKE_DEMO, SMOKE_MINIMAL}})

	// 5. A fresh changelog and backlog. The upstream's are its own history and
	//    to-do list, and CLAUDE.md tells an agent to work from TODO.md. The new
	//    changelog records the template release the fork started from: the
	//    question the upstream's changelog answers later is "what changed since".
	changelog, _ := strings.replace_all(MIN_CHANGELOG, "TEMPLATE_VERSION", template_version())
	put("CHANGELOG.md", changelog)
	put("TODO.md", MIN_TODO)
}

// The newest release in the upstream CHANGELOG.md, noting unreleased changes on
// top of it.
@(private = "file")
template_version :: proc() -> string {
	i := load("CHANGELOG.md")
	if i < 0 {
		return ""
	}
	s := changes[i].content
	unreleased := false
	for line in strings.split_lines_iterator(&s) {
		end := strings.index_byte(line, ']')
		if !strings.has_prefix(line, "## [") || end < 0 {
			unreleased ||= strings.has_prefix(line, "- ") // only [Unreleased] precedes the first release
			continue
		}
		v := line[len("## ["):end]
		if v == "Unreleased" {
			continue
		}
		return unreleased ? strings.concatenate({v, " plus unreleased changes"}) : v
	}
	problem("CHANGELOG.md: no release heading (`## [x.y.z]`) to record the template version from")
	return ""
}
