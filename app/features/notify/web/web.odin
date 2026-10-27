package notify_web

// ---- notify: routes, the member topic and send (PLAN §14.2, §6.2) -------------------------
//
// `send` is the one web-to-web import (§6.2): a producer (chat's mentions, the bot's
// late replies) calls notify_web.send(user, kind, ref, html), which stores the item
// and pushes it on notify.user:<id>, a member row: the layout's #live carries it on
// every page of theirs, so the log and every `.notify-count` follow at once.

import "core:strings"
import "core:time"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/obs"
import "../../../platform/store"
import "../../../platform/web"
import "../../../platform/workers"
import notify ".."
import m "../models"
import notify_views "../views"

// notify.user rides the layout's #live (hx-sse) on every page of a member's.
EXTS :: web.Exts{.Sse}

ROUTES := [?]web.Route {
	{.Get, "/notify", page, .Account_Self, {.Private}, 0},
	{.Get, "/notify/list", list, .Account_Self, {.Fragment}, 0},
	{.Post, "/notify/read", read_all, .Account_Self, {.Fragment}, 0},
}

USER :: "notify.user"

TOPICS := [?]hub.Topic {
	{family = USER, policy = .Queue, member = true, perm = .Account_Self},
}

JOBS := [?]workers.Job {
	{"notify.prune", time.Hour, prune},
}

// ---- send ------------------------------------------------------------------------------------

// Stores a notification for `user` and pushes it to them: `kind` is the producer's
// namespaced name, `ref` a path on this site ("" for none), `html` its line, escaped
// by the producer. A refused one (a bug in the producer) is logged and dropped.
send :: proc(user: u64, kind, ref, line: string) {
	if why := notify.check(user, kind, ref, line); why != "" {
		if l, ok := obs.begin(.Warning, "notify", "refused"); ok {
			obs.str(&l, "kind", kind)
			obs.str(&l, "why", why)
			obs.end(&l)
		}
		return
	}
	op := store.new_op(m.Add, 2 * (len(kind) + len(ref) + len(line)))
	a := store.op_allocator(op)
	op.user = user
	op.kind, op.ref, op.html = strings.clone(kind, a), strings.clone(ref, a), strings.clone(line, a)
	op.done = sent
	if !notify.add(op) { store.free_op(op) }
}

@(private)
sent :: proc(o: ^store.Op) {
	op := (^m.Add)(o)
	defer store.free_op(op)
	if op.err != .None { return }
	hub.publish(topic(op.user), notify_views.pushed(op.result, op.unread))
}

topic :: proc(user: u64) -> string {
	return strings.concatenate({USER, ":", hub.member_key({id = user})}, context.temp_allocator)
}

// ---- pages ----------------------------------------------------------------------------------

@(private)
page :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	items := make([dynamic]m.Item, context.temp_allocator)
	if err := notify.list(v.id, &items); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	web.render_page(req, res, "Inbox", "/notify", "Your notifications.", notify_views.page(items[:], notify.unread(v.id)))
}

// The log's items: what a resync refetches.
@(private)
list :: proc(req: ^web.Request, res: ^web.Response) {
	items := make([dynamic]m.Item, context.temp_allocator)
	if err := notify.list(web.viewer(req).id, &items); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	b := strings.builder_make(context.temp_allocator)
	notify_views.items(&b, items[:])
	web.respond_html(res, strings.to_string(b))
}

// Marks everything read: the log again, and every count to 0.
@(private)
read_all :: proc(req: ^web.Request, res: ^web.Response) {
	v := web.viewer(req)
	if err := notify.mark_read(v.id); err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	items := make([dynamic]m.Item, context.temp_allocator)
	_ = notify.list(v.id, &items)
	b := strings.builder_make(context.temp_allocator)
	notify_views.items(&b, items[:])
	html.w(&b, `<span hx-swap-oob="innerHTML:.notify-count">0</span>`)
	web.respond_html(res, strings.to_string(b))
}

// The home page's card: a member's count and newest few; a guest's nothing.
home_card :: proc(b: ^strings.Builder, v: authz.Viewer) {
	if !authz.can(v, .Account_Self) { return }
	items := make([dynamic]m.Item, context.temp_allocator)
	_ = notify.list(v.id, &items)
	notify_views.card(b, items[:], notify.unread(v.id))
}

@(private)
prune :: proc() {
	if n := notify.prune(); n > 0 {
		if l, ok := obs.begin(.Debug, "notify", "pruned"); ok {
			obs.num(&l, "n", i64(n))
			obs.end(&l)
		}
	}
}
