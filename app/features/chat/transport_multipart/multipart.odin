package chat_transport_multipart

// ---- chat over one long multipart response: transport D (PLAN §14.1) -----------------------
//
// The pane holds hx-multipart:connect; each message is a part whose HX-Part-ID is its
// id (the hub writes the rowid it was published with), so a reconnect's
// HX-Last-Part-ID asks for what came after it, and the first connect for the room's
// last SNAPSHOT. The composer POSTs, as SSE's does.

import "core:strconv"
import "core:strings"

import "../../../platform/hub"
import "../../../platform/stream"
import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "multipart"

EXTS :: web.Exts{.Multipart, .Pending}

wiring :: proc(r: m.Room) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, ` hx-multipart:connect="/chat/r/`)
	chat_views.esc(&b, r.slug)
	strings.write_string(&b, `/parts"`)
	return {pane = strings.to_string(b), composer = chat_views.post_composer(r)}
}

// GET /chat/r/<slug>/parts.
parts :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	last, resumed := web.parse_digits(web.header(req, "hx-last-part-id"))
	c := stream.multipart_begin(res, .Mixed, nil, proc(c: ^stream.Conn) { hub.unsubscribe((^hub.Sub)(c.user)) })
	if c == nil { return } // admission answered 503 or 429
	// Subscribed first, as the socket is: a message between the two comes twice, never not.
	c.user = hub.subscribe(c, {chat.room_topic(r.id)})
	msgs := make([dynamic]m.Message, 0, chat.SNAPSHOT, context.temp_allocator)
	err = chat.after(r.id, i64(last), &msgs) if resumed else chat.recent(r.id, &msgs)
	if err != .None || len(msgs) == 0 { return }
	b := strings.builder_make(context.temp_allocator)
	chat_views.partial(&b, r.id, r.slug, msgs[:])
	buf: [24]byte
	stream.multipart_part(c, strings.to_string(b), {{"HX-Part-ID", strconv.write_int(buf[:], msgs[len(msgs) - 1].id, 10)}})
}
