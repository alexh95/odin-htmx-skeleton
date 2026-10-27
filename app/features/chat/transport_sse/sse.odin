package chat_transport_sse

// ---- chat over the page's SSE stream: transport B (PLAN §14.1, §9.1) -----------------------
//
// No connection of its own: the room's topic rides the layout's #live beside the
// member's and the room's presence (D14), and the composer POSTs. A reconnect replays
// from the hub's ring; a cursor from another process gets `resync`, and the log
// refetches the room's last messages (the poll transport's route, with no tag).

import "core:fmt"
import "core:strings"

import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "sse"

EXTS :: web.Exts{.Sse, .Pending}

wiring :: proc(r: m.Room) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, ` hx-get="/chat/r/`)
	chat_views.esc(&b, r.slug)
	strings.write_string(&b, `/since" hx-trigger="resync from:body" hx-swap="none"`)
	return {pane = strings.to_string(b), composer = chat_views.post_composer(r)}
}

// The room's topic for the page's #live: from the newest message it rendered when
// ids outlive the process (a keyset replay, D13), else from the render-time cursor.
live_topic :: proc(r: m.Room, newest: i64) -> string {
	if chat.PERSISTED && newest > 0 { return fmt.tprintf("%s@%d", chat.room_topic(r.id), newest) }
	return chat.room_topic(r.id)
}
