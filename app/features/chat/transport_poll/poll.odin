package chat_transport_poll

// ---- chat by polling: transport C (PLAN §14.1) ---------------------------------------------
//
// The pane asks every 2 s what changed since the room's version it last saw, which
// hx-ptag carries both ways (HX-PTag): nothing new is a 304 with no body, so an idle
// room costs a few hundred bytes a poll. Edits and tombstones move the version too, so
// they arrive the same way. With no tag (the first poll, the SSE transport's resync)
// the answer is the room's last SNAPSHOT.

import "core:fmt"
import "core:strconv"
import "core:strings"

import "../../../platform/web"
import chat ".."
import m "../models"
import chat_views "../views"

NAME :: "poll"

EXTS :: web.Exts{.Ptag, .Pending}

EVERY :: "2s"

wiring :: proc(r: m.Room, ver: i64) -> chat_views.Wiring {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, ` hx-get="/chat/r/`)
	chat_views.esc(&b, r.slug)
	fmt.sbprintf(&b, `/since" hx-trigger="every %s" hx-ptag="%d" hx-swap="none"`, EVERY, ver)
	return {pane = strings.to_string(b), composer = chat_views.post_composer(r)}
}

// GET /chat/r/<slug>/since, with HX-PTag: the room's version.
since :: proc(req: ^web.Request, res: ^web.Response) {
	r, err := chat.room(req.url_params[0])
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	msgs := make([dynamic]m.Message, 0, 16, context.temp_allocator)
	ver: i64
	// A poll whose tag the room can't serve whole gets the snapshot, which replaces the log:
	// upserted, it kept what the page had with a silent gap before the newest (M2-35). SSE's
	// resync (no tag) still upserts: after a restart the room is new and empty, and a
	// replace would cost the page everything it had (D37).
	whole := false
	tag, has := web.header(req, "hx-ptag")
	from, ok := web.parse_digits(tag)
	if has && ok {
		reached: bool
		ver, reached, err = chat.changed(r.id, i64(from), &msgs)
		if err == .None && ver == i64(from) {
			web.respond_status(res, .Not_Modified)
			return
		}
		if err == .None && !reached {
			clear(&msgs)
			ver, err = chat.snapshot(r.id, &msgs)
			whole = true
		}
	} else {
		ver, err = chat.snapshot(r.id, &msgs)
	}
	if err != .None {
		web.respond_store_error(req, res, err)
		return
	}
	buf: [24]byte
	web.set_header(res, "hx-ptag", strconv.write_int(buf[:], ver, 10))
	b := strings.builder_make(context.temp_allocator)
	chat_views.partial(&b, r.id, r.slug, msgs[:], swap = "innerHTML" if whole else "upsert sort")
	web.respond_html(res, strings.to_string(b))
}
