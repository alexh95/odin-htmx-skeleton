package main

import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:testing"

import "../../platform/app"
import "../../platform/html"
import "../../platform/web"

// The boot checks of §6.1 over this profile's tables, as `CMD=test build.sh skeleton`
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

// A deliberately bad table trips the boot checks it breaks, each once, and nothing else.
@(test)
bad_table_fails_boot_checks :: proc(t: ^testing.T) {
	arena: virtual.Arena
	_ = virtual.arena_init_growing(&arena)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator
	h :: proc(req: ^web.Request, res: ^web.Response) {}
	a := []web.Route {
		{.Get, "/contacts", h, .Public, {}, 0},
		{.Get, "/contacts", h, .Public, {}, 0}, // 1: mounted twice
		{.Post, "/contacts", nil, .Public, {}, 0}, // 1: no handler
	}
	b := []web.Route {
		{.Get, "/contacts/(%d+)", h, .Public, {}, 0}, // 5: a's router key
	}
	hosts := []app.Host{{name = "main", identity = true, routes = {{"a", a}, {"b", b}}}} // 3: no root row
	problems := app.dry_check(hosts, nil, BUNDLE_EXTS)
	want := []string{"mounted twice", "has no handler", "is claimed by a and b", "0 root rows"}
	testing.expectf(t, len(problems) == len(want), "problems: %v", problems)
	for w in want {
		said := false
		for p in problems { said ||= strings.contains(p, w) }
		testing.expectf(t, said, "no problem says %q: %v", w, problems)
	}
}

// The router, here because platform/web reaches the family collections and can't be
// tested alone: a request tries only its own method's rows, a literal row matches by
// comparison, and only a miss lists the other methods for the 405.
@(test)
router_finds_rows :: proc(t: ^testing.T) {
	arena: virtual.Arena
	_ = virtual.arena_init_growing(&arena)
	defer virtual.arena_destroy(&arena)
	runner := context.allocator
	context.allocator = virtual.arena_allocator(&arena)
	context.temp_allocator = context.allocator
	r: web.Router
	web.router_mount(&r, {
		{method = .Get, pattern = "/"},
		{method = .Get, pattern = "/contacts"},
		{method = .Get, pattern = "/contacts/(%d+)"},
		{method = .Get, pattern = "/contacts/(.+)"}, // after (%d+): mount order decides
		{method = .Post, pattern = "/contacts"},
		{method = .Post, pattern = "/contacts/(%d+)"},
		{method = .Delete, pattern = "/contacts/(%d+)"},
		{method = .Get, pattern = "/favicon%.ico"},
		{method = .Get, pattern = "/ui/(.+)"},
		{method = .Get, pattern = "/ui/tab"}, // its own two-segment bucket, tried before "/ui"
	})
	// A lookup allocates only in the request arena: anything on context.allocator leaks here.
	context.allocator = runner
	Case :: struct {
		method: web.Method,
		path:   string,
		id:     string, // the row's id, "" for none
		param:  string,
		allow:  []string,
	}
	cases := []Case {
		{.Get, "/", "GET /", "", nil},
		{.Post, "/contacts", "POST /contacts", "", nil},
		{.Delete, "/contacts/12", "DELETE /contacts/(%d+)", "12", nil},
		{.Get, "/contacts/12", "GET /contacts/(%d+)", "12", nil},
		{.Get, "/contacts/ab", "GET /contacts/(.+)", "ab", nil},
		{.Get, "/ui/tab", "GET /ui/tab", "", nil},
		{.Get, "/ui/x", "GET /ui/(.+)", "x", nil},
		{.Get, "/favicon.ico", "GET /favicon%.ico", "", nil},
		{.Get, "/faviconXico", "", "", nil},
		{.Put, "/contacts/12", "", "", {"DELETE", "GET", "HEAD", "POST"}},
		{.Delete, "/contacts", "", "", {"GET", "HEAD", "POST"}},
	}
	for c in cases {
		m, params, allow := web.router_find(&r, c.method, c.path)
		testing.expectf(t, (m.id if m != nil else "") == c.id, "%v %s: row %v", c.method, c.path, m)
		if c.param != "" { testing.expectf(t, len(params) == 1 && params[0] == c.param, "%s: params %v", c.path, params) }
		testing.expectf(t, slice.equal(allow, c.allow), "%v %s: allow %v", c.method, c.path, allow)
	}
}

// The skeleton is on the vanilla client: html.behave writes a twin's name, which
// app.js dispatches on, and nothing for a behaviour with no twin. Every row's
// names fit what the gate and escaping.spec accept.
@(test)
behave_writes_twins :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, html.behave_attr(.Tabs), ` data-behave="tabs"`)
	testing.expect_value(t, html.behave_attr(.Reset_On_Success), ` data-behave="reset-on-success"`)
	testing.expect_value(t, html.behave_attr(.Copy_Text), ``)
	for row, x in html.BEHAVIOURS {
		hs_ok := len(row.hs) > 0 && row.hs[0] >= 'A' && row.hs[0] <= 'Z'
		for c in row.hs { hs_ok &&= (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') }
		testing.expectf(t, hs_ok, "%v: hyperscript name %q", x, row.hs)
		for c in row.vanilla { testing.expectf(t, (c >= 'a' && c <= 'z') || c == '-', "%v: vanilla name %q", x, row.vanilla) }
	}
}
