package demo

import "core:net"
import "core:strconv"
import "core:strings"
import "core:time"

import http "odin-http"

// ---- controllers --------------------------------------------------------
//
// The HTTP layer. Each handler parses the request, calls a service, renders a
// view and responds. Nothing here knows how the store works; nothing in the
// services knows it is being driven over HTTP.

// ---- request helpers ----------------------------------------------------

// Read a single query parameter, percent-decoded. odin-http hands us the raw
// query string (everything after '?'); we walk it once rather than building a
// map for the one key we want.
query_get :: proc(req: ^http.Request, key: string) -> string {
	q := req.url.query
	for part in strings.split_by_byte_iterator(&q, '&') {
		eq := strings.index_byte(part, '=')
		k := eq < 0 ? part : part[:eq]
		if k == key {
			return query_decode(eq < 0 ? "" : part[eq + 1:])
		}
	}
	return ""
}

query_int :: proc(req: ^http.Request, key: string, fallback: int) -> int {
	s := query_get(req, key)
	if s == "" {
		return fallback
	}
	return to_int(s)
}

@(private = "file")
to_int :: proc(s: string) -> int {
	n, _ := strconv.parse_int(s, 10)
	return n
}

@(private = "file")
query_decode :: proc(s: string) -> string {
	if s == "" {
		return ""
	}
	t := s
	if strings.index_byte(s, '+') >= 0 {
		t, _ = strings.replace_all(s, "+", " ", context.temp_allocator)
	}
	dec, ok := net.percent_decode(t, context.temp_allocator)
	return ok ? dec : t
}

render_page :: proc(res: ^http.Response, title, active, content: string) {
	http.respond_html(res, layout(title, active, content))
}

// ---- pages --------------------------------------------------------------

page_dashboard :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(res, "Dashboard", "/", view_dashboard())
}

page_components :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(res, "Components", "/components", view_components())
}

page_forms :: proc(req: ^http.Request, res: ^http.Response) {
	render_page(res, "Forms", "/forms", view_forms())
}

page_data :: proc(req: ^http.Request, res: ^http.Response) {
	p := service_page(query_get(req, "q"), "name", 1)
	render_page(res, "Data & CRUD", "/data", view_data(p))
}

// ---- search -------------------------------------------------------------

frag_search :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, view_search_results(query_get(req, "q")))
}

Contact_DTO :: struct {
	id:     int,
	name:   string,
	email:  string,
	role:   string,
	status: string,
	score:  int,
}

// The non-HTMX surface: same data, plain JSON. Proves the service layer stands
// on its own.
api_search :: proc(req: ^http.Request, res: ^http.Response) {
	q := strings.trim_space(query_get(req, "q"))
	rn := ROLE_NAMES
	sn := STATUS_NAMES
	out := make([dynamic]Contact_DTO, context.temp_allocator)
	for c in repo_list() {
		if q == "" || contact_matches(c, q) {
			append(&out, Contact_DTO{c.id, c.name, c.email, rn[c.role], sn[c.status], c.score})
		}
	}
	http.respond_json(res, out[:])
}

// ---- contacts table + CRUD ----------------------------------------------

frag_contacts :: proc(req: ^http.Request, res: ^http.Response) {
	sort := query_get(req, "sort")
	if sort == "" {
		sort = "name"
	}
	p := service_page(query_get(req, "q"), sort, query_int(req, "page", 1))
	http.respond_html(res, view_contacts_region(p))
}

// user_data passed through http.body. Allocated in the request arena so it
// survives until the (possibly deferred) body callback runs.
@(private = "file")
Form_Ctx :: struct {
	res: ^http.Response,
	id:  int,
}

contacts_create :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Form_Ctx)user
		res := ctx.res
		if err != nil {
			http.respond(res, http.Status.Bad_Request)
			return
		}
		form, ok := http.body_url_encoded(body)
		name := ok ? form["name"] : ""
		email := ok ? form["email"] : ""

		errs := validate_contact(name, email)
		if len(errs) > 0 {
			http.respond_html(res, view_toast("error", errs[0].msg, true))
			return
		}

		role, _ := role_from(ok ? form["role"] : "")
		c := repo_create(strings.trim_space(name), strings.trim_space(email), role, .Invited, 50)

		b := strings.builder_make(context.temp_allocator)
		view_contact_row(&b, c, true)
		w(&b, view_toast("success", "Contact added.", true))
		http.respond_html(res, strings.to_string(b))
	})
}

contacts_update :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	ctx.id = to_int(req.url_params[0])
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		ctx := cast(^Form_Ctx)user
		res := ctx.res

		form, _ := http.body_url_encoded(body)
		action := form["action"]

		c: Contact
		ok: bool
		if action == "cycle" {
			if cur, found := repo_get(ctx.id); found {
				next := Status((int(cur.status) + 1) % len(Status))
				c, ok = repo_set_status(ctx.id, next)
			}
		} else {
			c, ok = repo_get(ctx.id)
		}

		if !ok {
			http.respond(res, http.Status.Not_Found)
			return
		}
		b := strings.builder_make(context.temp_allocator)
		view_contact_row(&b, c, false)
		http.respond_html(res, strings.to_string(b))
	})
}

contacts_delete :: proc(req: ^http.Request, res: ^http.Response) {
	id := to_int(req.url_params[0])
	if !repo_delete(id) {
		http.respond(res, http.Status.Not_Found)
		return
	}
	// Empty body: the outerHTML swap replaces the row with nothing.
	http.respond_html(res, "")
}

// ---- forms --------------------------------------------------------------

validate_email_field :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := (cast(^Form_Ctx)user).res
		form, _ := http.body_url_encoded(body)
		email := strings.trim_space(form["email"])
		if email == "" {
			http.respond_html(res, "")
			return
		}
		if valid_email(email) {
			http.respond_html(res, view_field_msg(true, "Looks good."))
		} else {
			http.respond_html(res, view_field_msg(false, "That doesn't look like an email."))
		}
	})
}

forms_submit :: proc(req: ^http.Request, res: ^http.Response) {
	ctx := new(Form_Ctx, context.temp_allocator)
	ctx.res = res
	http.body(req, -1, ctx, proc(user: rawptr, body: http.Body, err: http.Body_Error) {
		res := (cast(^Form_Ctx)user).res
		form, _ := http.body_url_encoded(body)
		name := form["name"]
		email := form["email"]

		errs := validate_contact(name, email)
		if len(errs) > 0 {
			http.respond_html(res, view_form_errors(errs))
			return
		}

		role, _ := role_from(form["role"])
		status, _ := status_from(form["status"])
		score := clamp(to_int(form["score"]), 0, 100)
		c := repo_create(strings.trim_space(name), strings.trim_space(email), role, status, score)

		b := strings.builder_make(context.temp_allocator)
		w(&b, view_form_result(c))
		w(&b, view_toast("success", "Saved to the in-memory store.", true))
		http.respond_html(res, strings.to_string(b))
	})
}

// ---- ui fragments -------------------------------------------------------

ui_modal :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, view_modal())
}

ui_drawer :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, view_drawer())
}

ui_clear :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, "")
}

ui_tab :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_html(res, tab_panel(req.url_params[0]))
}

ui_toast :: proc(req: ^http.Request, res: ^http.Response) {
	kind := query_get(req, "kind")
	msg := kind == "error" ? "Something went sideways." : "That worked nicely."
	http.respond_html(res, view_toast(kind, msg, false))
}

ui_ping :: proc(req: ^http.Request, res: ^http.Response) {
	token := time.now()._nsec / 1_000_000
	rps := 40 + int(token % 60)
	http.respond_html(res, view_ping(token, rps))
}

// ---- static -------------------------------------------------------------

// HTMX is compiled into the binary (see routes.odin) and served from memory.
serve_htmx :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_file_content(res, "htmx.min.js", HTMX_JS)
}

// Everything else under /static is read from disk so CSS/JS edits show up on
// refresh without a recompile.
serve_static :: proc(req: ^http.Request, res: ^http.Response) {
	http.respond_dir(res, "/static/", "static", req.url.path)
}
