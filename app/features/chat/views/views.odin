package chat_views

// ---- chat: the views (PLAN §14.1, §9.1) ----------------------------------------------------
//
// A room is a live log, <div role="log" id="log-<room>"> of <article id="m-<id>">, in the
// page's first markup. Every message travels as one fragment whatever the transport,
// `<hx-partial hx-target="#log-<room>" hx-swap="upsert sort">`: upsert replaces an article
// it already has (an edit, a tombstone, a replay's duplicate) and sorts a new one in by
// its id, so a reconnect, a resync and the author's own reply never double a message.
// A message is rendered once for every reader; what differs per viewer is asked for
// (the menu) or marked by AutoScroll against the log's data-me. Only the body is
// ignored by htmx and hyperscript, so the message's own controls keep working.

import "core:fmt"
import "core:strings"
import "core:time"

import "../../../platform/html"
import chat ".."
import m "../models"

w :: html.w
esc :: html.esc

Room_Row :: struct {
	room:   m.Room,
	unread: int, // -1: never read
}

// What a transport adds to a room page (chat_web's switch asks the chosen one): the
// attributes of the pane that holds the log, and of the composer's form.
Wiring :: struct {
	pane:     string,
	composer: string,
}

// ---- the rooms ---------------------------------------------------------------------------

index_page :: proc(rows: []Room_Row, t: chat.Transport, may_create: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Chat", "Rooms on the LAN. They are kept in memory, so a restart empties them.")
	w(&b, `<section class="block chat-index"><ul class="chat-rooms">`)
	for r in rows {
		w(&b, `<li><a class="chat-room-link" href="/chat/r/`)
		esc(&b, r.room.slug)
		w(&b, `"><span class="chat-hash">#</span>`)
		esc(&b, r.room.name)
		w(&b, `</a> <span class="badge chat-unread unread-`)
		esc(&b, r.room.slug)
		w(&b, `">`)
		if r.unread > 0 { strings.write_int(&b, r.unread) }
		w(&b, `</span></li>`)
	}
	w(&b, `</ul>`)
	if may_create {
		w(&b, `<form class="chat-new" hx-post="/chat/rooms" hx-status:422="target:#room-error swap:innerHTML"><label for="room-name">New room</label><div class="chat-new-row"><input id="room-name" name="name" maxlength="40" required placeholder="Name"><button class="btn btn-primary" type="submit">Create</button></div><p class="field-msg form-error" id="room-error"></p></form>`)
	}
	connection(&b, t)
	w(&b, `</section>`)
	return strings.to_string(b)
}

// The "Connection" setting (§14.1): a compatibility mode for networks whose proxies
// kill WebSockets. A plain form, so it works with no script at all.
connection :: proc(b: ^strings.Builder, t: chat.Transport) {
	w(b, `<form class="chat-conn" method="post" action="/chat/transport"><label for="transport">Connection</label><select id="transport" name="transport">`)
	for row, k in chat.TRANSPORTS {
		w(b, `<option value="`)
		w(b, row.name)
		w(b, `"`)
		if k == t { w(b, ` selected`) }
		w(b, `>`)
		w(b, row.label)
		w(b, `</option>`)
	}
	w(b, `</select><button class="btn btn-outline" type="submit">Use</button></form>`)
}

// What a Guest sees at /chat: chat is the LAN's (ANSWERS round 9; §14.1).
lan_notice_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Comms", "Chat", "Chat is open on the LAN.")
	w(&b, `<section class="block"><article class="card chat-lan"><p>Chat is for the people on this network. On it? <a href="/login?next=/chat">Pick a nickname</a> and the rooms open.</p></article></section>`)
	return strings.to_string(b)
}

// ---- a room ------------------------------------------------------------------------------

// The composer of the three transports that post over HTTP (sse, poll, multipart):
// the message comes back in the response, and to everyone else on the room's
// stream; hx-pending shows it at once, a 422 goes to the form's error slot and a
// 429 to the toasts.
post_composer :: proc(r: m.Room) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, ` hx-post="/chat/r/`)
	esc(&b, r.slug)
	fmt.sbprintf(&b, `" hx-target="#log-%d" hx-swap="beforeend" hx-pending="#chat-pending" hx-status:422="target:#err-%d swap:innerHTML" hx-status:429="target:#toasts swap:beforeend"`, r.id, r.id)
	return strings.to_string(b)
}

room_page :: proc(r: m.Room, msgs: []m.Message, here: []chat.Presence_Change, me: u64, t: chat.Transport, wiring: Wiring) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<section class="chat-room" data-room="`)
	esc(&b, r.slug)
	w(&b, `"><header class="chat-head"><h1><span class="chat-hash">#</span>`)
	esc(&b, r.name)
	w(&b, `</h1>`)
	if !chat.PERSISTED { w(&b, `<span class="badge" title="Kept in memory: a restart empties it">ephemeral</span>`) }
	w(&b, `<span class="chat-via muted">`)
	w(&b, chat.TRANSPORTS[t].label)
	w(&b, `</span><a class="chat-back" href="/chat">All rooms</a></header><div class="chat-main">`)

	fmt.sbprintf(&b, `<div class="chat-pane" id="pane-%d"%s>`, r.id, wiring.pane)
	fmt.sbprintf(&b, `<div id="log-%d" class="chat-log" role="log" aria-label="Messages" data-me="%d"`, r.id, me)
	html.behave(&b, .Auto_Scroll)
	w(&b, `>`)
	for msg, i in msgs { message(&b, msg, r.slug, i == len(msgs) - 1) }
	fmt.sbprintf(&b, `</div><div id="typing-%d" class="chat-typing" aria-live="polite" data-me="%d"`, r.id, me)
	html.behave(&b, .Auto_Scroll) // marks the reader's own "is typing", which CSS hides
	w(&b, `></div>`)

	fmt.sbprintf(&b, `<form class="chat-composer" id="say-%d"%s`, r.id, wiring.composer)
	html.behave(&b, .Composer)
	fmt.sbprintf(&b, `><textarea id="body-%d" name="body" rows="1" maxlength="%d" required aria-label="Message" placeholder="Message #`, r.id, chat.MAX_BODY)
	esc(&b, r.slug)
	w(&b, `" hx-post="/chat/r/`)
	esc(&b, r.slug)
	fmt.sbprintf(&b, `/typing" hx-trigger="input changed throttle:2s" hx-swap="none"></textarea><button class="btn btn-primary" type="submit">Send</button><p class="field-msg form-error" id="err-%d"></p></form></div>`, r.id)

	fmt.sbprintf(&b, `<aside class="chat-side"><h2>Here</h2><div id="who-%d" class="chat-who">`, r.id)
	for p in here { who(&b, p) }
	// What hx-pending shows while a post is on its way; the typed text arrives as data-body.
	w(&b, `</div></aside></div><template id="chat-pending"><article class="chat-msg pending"><p class="chat-body muted">Sending…</p></article></template></section>`)
	return strings.to_string(b)
}

// One message. The newest a reader has carries the read receipt: a POST when it
// scrolls into view, never a GET a preload could fire (§14.1).
message :: proc(b: ^strings.Builder, msg: m.Message, slug: string, newest: bool) {
	fmt.sbprintf(b, `<article id="m-%d" class="chat-msg%s" data-author="%d"`, msg.id, " gone" if msg.gone else "", msg.author)
	if newest {
		w(b, ` hx-post="/chat/r/`)
		esc(b, slug)
		fmt.sbprintf(b, `/read?upto=%d" hx-trigger="intersect once" hx-swap="none"`, msg.id)
	}
	w(b, `><header>`)
	html.avatar(b, i64(msg.author % (1 << 53)), msg.name)
	w(b, `<b class="chat-name">`)
	esc(b, msg.name)
	w(b, `</b> <time datetime="`)
	w(b, iso(msg.at))
	w(b, `">`)
	esc(b, html.time_ago(msg.at))
	w(b, `</time>`)
	if msg.edited != 0 && !msg.gone { w(b, ` <small class="muted">(edited)</small>`) }
	if !msg.gone {
		fmt.sbprintf(b, `<button class="chat-more" type="button" aria-label="Message actions" hx-get="/chat/m/%d/menu" hx-target="#mm-%d">⋯</button>`, msg.id, msg.id)
	}
	w(b, `</header>`)
	if msg.gone {
		w(b, `<p class="chat-body muted">Message deleted.</p>`)
	} else {
		w(b, `<div class="chat-body" hx-ignore data-disable-scripting>`)
		esc(b, msg.body)
		w(b, `</div>`)
	}
	// The menu's slot: a click outside the message, or Escape, empties it.
	fmt.sbprintf(b, `<div class="chat-menu" id="mm-%d"`, msg.id)
	html.behave(b, .Dismiss)
	w(b, `></div></article>`)
}

// Messages as one fragment for the room's log (every transport sends this).
partial :: proc(b: ^strings.Builder, room: i64, slug: string, msgs: []m.Message, newest_last := true) {
	if len(msgs) == 0 { return }
	fmt.sbprintf(b, `<hx-partial hx-target="#log-%d" hx-swap="upsert sort">`, room)
	for msg, i in msgs { message(b, msg, slug, newest_last && i == len(msgs) - 1) }
	w(b, `</hx-partial>`)
}

one :: proc(room: i64, slug: string, msg: m.Message) -> string {
	b := strings.builder_make(context.temp_allocator)
	partial(&b, room, slug, {msg})
	return strings.to_string(b)
}

// ---- a message's menu and its edit form ----------------------------------------------------
//
// Asked for when wanted (GET /chat/m/<id>/menu), so it is rendered for its viewer.

menu :: proc(msg: m.Message, slug: string, may_change: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<div class="chat-actions"><a href="/chat/r/`)
	esc(&b, slug)
	fmt.sbprintf(&b, `#m-%d">Link</a>`, msg.id)
	if may_change {
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-get="/chat/m/%d/edit" hx-target="#mm-%d">Edit</button>`, msg.id, msg.id)
		fmt.sbprintf(&b, `<button class="btn btn-ghost" type="button" hx-post="/chat/m/%d/delete" hx-target="#mm-%d">Delete</button>`, msg.id, msg.id)
	}
	w(&b, `</div>`)
	return strings.to_string(b)
}

// The edit form, filled with `body` (what was typed, after a refusal) and its reason.
edit_form :: proc(id: i64, body, problem: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<form class="chat-edit" hx-post="/chat/m/%d/edit" hx-target="#mm-%d"><textarea id="edit-%d" name="body" rows="2" maxlength="%d" required aria-label="Edit the message">`, id, id, id, chat.MAX_BODY)
	esc(&b, body)
	w(&b, `</textarea><button class="btn btn-primary" type="submit">Save</button>`)
	if problem != "" {
		w(&b, `<p class="field-msg form-error">`)
		esc(&b, problem)
		w(&b, `</p>`)
	}
	w(&b, `</form>`)
	return strings.to_string(b)
}

// ---- presence, typing and unread counts -------------------------------------------------------

who :: proc(b: ^strings.Builder, p: chat.Presence_Change) {
	fmt.sbprintf(b, `<span id="p-%d-%d" class="who who-%s">`, p.room, p.who, "away" if p.state == .Away else "online")
	esc(b, p.name)
	w(b, `</span>`)
}

// A presence change for chat.presence:<room>: upserted into the list, or deleted.
presence :: proc(p: chat.Presence_Change) -> string {
	b := strings.builder_make(context.temp_allocator)
	if p.state == .Gone {
		fmt.sbprintf(&b, `<span hx-swap-oob="delete:#p-%d-%d"></span>`, p.room, p.who)
	} else {
		fmt.sbprintf(&b, `<hx-partial hx-target="#who-%d" hx-swap="upsert sort">`, p.room)
		who(&b, p)
		w(&b, `</hx-partial>`)
	}
	return strings.to_string(b)
}

// "<name> is typing": a re-upsert replaces it, which restarts its CSS fade; Expire
// removes it on the hyperscript client.
typing :: proc(room: i64, id: u64, name: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, `<hx-partial hx-target="#typing-%d" hx-swap="upsert"><span id="t-%d-%d" class="typing-who" data-author="%d"`, room, room, id, id)
	html.behave(&b, .Expire)
	w(&b, `>`)
	esc(&b, name)
	w(&b, ` is typing…</span></hx-partial>`)
	return strings.to_string(b)
}

// A member's unread count for a room, into every `.unread-<slug>` of theirs.
unread :: proc(slug: string, n: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<span hx-swap-oob="innerHTML:.unread-`)
	esc(&b, slug)
	w(&b, `">`)
	if n > 0 { strings.write_int(&b, n) }
	w(&b, `</span>`)
	return strings.to_string(b)
}

// A mention, for the member's Inbox.
mention_line :: proc(by, room, body: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	w(&b, `<b>`)
	esc(&b, by)
	w(&b, `</b> mentioned you in <b>#`)
	esc(&b, room)
	w(&b, `</b>: `)
	n := 0
	for _, i in body {
		if n == 80 {
			esc(&b, body[:i])
			w(&b, `…`)
			return strings.to_string(b)
		}
		n += 1
	}
	esc(&b, body)
	return strings.to_string(b)
}

@(private)
iso :: proc(at: i64) -> string {
	s, _ := time.time_to_rfc3339(time.unix(at, 0), 0, false, context.temp_allocator)
	return s
}
