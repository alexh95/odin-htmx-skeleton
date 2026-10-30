package dbview_web

// ---- dbview: /admin/dbview (PLAN §15.4, D36) ----------------------------------------------------
//
// An admin's own read-only SQL. The query runs on the store's query pool (a scan never holds a
// loop), on that thread's own read-only reader, so it never takes the writer's lock; the answer
// comes back as a deferred response. Admins with Admin_Db, from the LAN, stepped up; every query
// is audited (`dbview.query`, the SQL in its detail).

import "base:runtime"
import "core:mem/virtual"
import "core:strings"

import "../../../platform/html"
import "../../../platform/web"
import "../../../platform/workers"
import store_sqlite "../../../platform/store/sqlite"
import dbview ".."
import dbview_views "../views"
import audit_store "store:audit"

EXTS :: web.Exts{}

ROUTES := [?]web.Route {
	{.Get, "/admin/dbview", page, .Admin_Db, {.Private, .Lan_Only, .Step_Up}, 0},
	{.Post, "/admin/dbview", run, .Admin_Db, {.Fragment, .Lan_Only, .Step_Up}, dbview.MAX_SQL * 3 + 64},
}

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Admin", "Database", "Read-only SQL against this site's database.")
	dbview_views.page(&b)
	web.render_page(req, res, "Database", "/admin/dbview", "Read-only SQL.", strings.to_string(b))
}

// A query on its way: the pool task, the deferred response, and an arena for what it finds.
@(private)
Querying :: struct {
	using task: workers.Task,
	deferred:   web.Deferred,
	arena:      virtual.Arena,
	sql:        string, // in the arena
	html:       string, // in the arena: the answer, rendered on the pool thread
}

// POST /admin/dbview: sql.
@(private)
run :: proc(req: ^web.Request, res: ^web.Response) {
	sql, problem := dbview.check(web.form(req)["sql"])
	if problem != "" {
		web.respond_html(res, html.field_msg(false, problem), .Unprocessable_Content)
		return
	}
	c := web.ctx()
	buf: [16]byte
	cut := sql[:min(len(sql), 200)]
	audit_store.append({i64(c.viewer.id), c.viewer.name, web.client_id(c.client, buf[:])}, "dbview.query", {"database", 0}, "", cut)

	q := new(Querying, runtime.heap_allocator())
	if virtual.arena_init_growing(&q.arena) != nil {
		free(q, runtime.heap_allocator())
		web.respond_store_error(req, res, .Failed)
		return
	}
	q.sql = strings.clone(sql, virtual.arena_allocator(&q.arena))
	q.run = proc(t: ^workers.Task) {
		q := (^Querying)(t)
		a := virtual.arena_allocator(&q.arena)
		r, problem := dbview.query(q.sql, a)
		b := strings.builder_make(a)
		dbview_views.result(&b, r, problem)
		q.html = strings.to_string(b)
	}
	q.done = answered
	web.defer_response(req, res, &q.deferred)
	if !store_sqlite.query(&q.task) {
		if r := web.resume(&q.deferred); r != nil {
			web.respond_store_error(req, r, .Busy)
			web.finish(&q.deferred, r)
		}
		release(q)
	}
}

@(private)
answered :: proc(t: ^workers.Task) {
	q := (^Querying)(t)
	defer release(q)
	res := web.resume(&q.deferred)
	if res == nil { return }
	req := web.request(&q.deferred)
	switch {
	case !q.ran:     web.respond_store_error(req, res, .Busy)
	case q.crashed:  web.respond_store_error(req, res, .Failed)
	case:            web.respond_html(res, q.html)
	}
	web.finish(&q.deferred, res)
}

@(private)
release :: proc(q: ^Querying) {
	virtual.arena_destroy(&q.arena)
	free(q, runtime.heap_allocator())
}
