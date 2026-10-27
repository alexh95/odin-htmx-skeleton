package chat_transport_ws

// ---- chat over a WebSocket: transport A, the default (PLAN §14.1) --------------------------
//
// The room pane is the socket (hx-ws:connect) and the composer sends on it (hx-ws:send,
// JSON in). Each (re)connect first gets the room's last SNAPSHOT, then everything the
// room's topic carries; upsert drops what it already has, so a reconnect needs no
// cursor. A frame is posted the way a form's POST is, by chat_web (`post`), which this
// package can't import.

import "base:runtime"
import "core:strings"

import "../../../platform/authz"
import "../../../platform/html"
import "../../../platform/hub"
import "../../../platform/stream"
import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "ws"

EXTS :: web.Exts{.Ws}

// §17.5: frames a second per connection, then 1008.
MAX_RATE :: 20

Socket :: struct {
	conn: ^stream.Conn,
	sub:  ^hub.Sub,
	room: m.Room,       // slug and name on the heap
	who:  authz.Viewer, // name on the heap
}

// Set by chat_web at init: a frame's body, posted (or refused back down the socket).
post: proc(s: ^Socket, body: string)

wiring :: proc(r: m.Room) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	html_esc(&b, ` hx-ws:connect="/chat/r/`, r.slug, `/ws"`)
	return {pane = strings.to_string(b), composer = ` hx-ws:send`}
}

// GET /chat/r/<slug>/ws.
socket :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	c, uerr := stream.ws_upgrade(req, res, on_message, on_close, max_rate = MAX_RATE)
	if uerr != .None { return }
	v := web.viewer(req)
	s := new(Socket, heap())
	s.conn = c
	s.room = {id = r.id, slug = strings.clone(r.slug, heap()), name = strings.clone(r.name, heap()), at = r.at}
	s.who = {id = v.id, role = v.role, name = strings.clone(v.name, heap())}
	c.user = s
	// Subscribed before the snapshot is read: a message between the two arrives
	// twice rather than never, and upsert keeps one.
	s.sub = hub.subscribe(c, {chat.room_topic(r.id)})
	msgs := make([dynamic]m.Message, 0, chat.SNAPSHOT, context.temp_allocator)
	if chat.recent(r.id, &msgs) == .None && len(msgs) > 0 {
		html, _ := chat_views.snapshot(r.id, r.slug, msgs[:], stream.backlog_budget())
		stream.ws_send_text(c, html)
	}
}

// Writes `html` (a refusal, a toast) to this socket alone.
send :: proc(s: ^Socket, html: string) {
	stream.ws_send_text(s.conn, html)
}

@(private)
on_message :: proc(c: ^stream.Conn, text: bool, data: []byte) {
	In :: struct {
		body: string,
	}
	msg: In
	if !text { return }
	if !stream.ws_json(data, &msg) {
		// Refused unparsed (stream.ws_json's bounds), so the member hears why it went nowhere.
		send((^Socket)(c.user), html.toast("error", "That message couldn't be read: too many brackets?", true))
		return
	}
	if post != nil { post((^Socket)(c.user), msg.body) }
}

@(private)
on_close :: proc(c: ^stream.Conn) {
	s := (^Socket)(c.user)
	if s == nil { return }
	hub.unsubscribe(s.sub)
	delete(s.room.slug, heap())
	delete(s.room.name, heap())
	delete(s.who.name, heap())
	free(s, heap())
}

@(private)
html_esc :: proc(b: ^strings.Builder, before, value, after: string) {
	strings.write_string(b, before)
	chat_views.esc(b, value)
	strings.write_string(b, after)
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
