package lab_views

// ---- lab: the stream contract pages (PLAN §15.5) ---------------------------------------
//
// Each page uses a stream the way §9.1 says a real page will: one layout SSE
// stream (#live) feeding a live log by OOB, one hx-ws:connect inside the swapped
// region, hx-multipart for parts that land in their own targets. Every value
// from the request is escaped; keys are checked by the web package first.

import "core:strings"

import "../../../platform/html"

// The layout stream for `topic`, resuming after `after` (the hub's cursor at
// render time). The URL goes through esc, so `&` is written `&amp;`.
live :: proc(b: ^strings.Builder, topic, after: string) {
	html.w(b, `<div id="live" hx-sse:connect="/events?t=`)
	html.esc(b, topic)
	html.w(b, `&amp;after=`)
	html.esc(b, after)
	html.w(b, `"></div>`)
}

index_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lab", "The stream contract", "SSE, WebSocket and multipart from the Odin server to htmx 4's extensions, each used the way a real page uses it.")
	html.w(&b, `<section class="block"><div class="lab-grid">`)
	card :: proc(b: ^strings.Builder, href, title, text: string) {
		html.w(b, `<a class="card lab-card" href="`)
		html.w(b, href)
		html.w(b, `"><h2>`)
		html.esc(b, title)
		html.w(b, `</h2><p class="muted">`)
		html.esc(b, text)
		html.w(b, `</p></a>`)
	}
	card(&b, "/lab/streams", "All three on one page", "The page contract: one layout SSE stream, one socket in the main region and a multipart panel, under the strict CSP.")
	card(&b, "/lab/streams/live", "hx-sse", "A live log fed by out-of-band swaps, resumed by Last-Event-ID or the render-time cursor, refetched on resync.")
	card(&b, "/lab/streams/chat", "hx-ws", "A room: hx-ws:send sends JSON, every socket in the room gets the escaped message back.")
	card(&b, "/lab/streams/mp", "hx-multipart", "One response in parts, each swapped into its own target as it arrives; a feed that resumes by HX-Last-Part-ID.")
	html.w(&b, `</div></section>`)
	return strings.to_string(b)
}

// /lab/streams/live: the layout stream feeding #feed, a fragment refetched on
// `resync`, and a button whose hx-post is answered with a stream (the bot's shape).
live_page :: proc(topic, key, after: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	live(&b, topic, after)
	html.page_head(&b, "Lab", "hx-sse", "Unnamed events swap out of band into the log; a cursor from another process gets `resync`, which refetches.")
	html.w(&b, `<section class="block lab"><div id="feed" class="lab-log" role="log" aria-label="Feed"></div>`)
	refetch(&b, key)
	html.w(&b, `<button id="ask" class="btn btn-primary" type="button" hx-post="/lab/sse/tick?n=3&amp;ms=150" hx-target="#tokens" hx-swap="beforeend">Ask</button>`)
	html.w(&b, `<div id="tokens" class="lab-log" role="log" aria-label="Answer"></div></section>`)
	return strings.to_string(b)
}

chat_page :: proc(room, tag: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lab", "hx-ws", "One socket inside the swapped region; the room's messages come back as escaped out-of-band HTML.")
	room_section(&b, room, tag)
	return strings.to_string(b)
}

mp_page :: proc(tag: string, count: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lab", "hx-multipart", "Each part names its own target and swaps as soon as its Content-Length is in.")
	mp_panel(&b, tag, count)
	return strings.to_string(b)
}

// /lab/streams: the page contract in one page (§9.1).
all_page :: proc(topic, key, room, tag, after: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	live(&b, topic, after)
	html.page_head(&b, "Lab", "The page contract", "One layout SSE stream, one socket in the main region and a multipart panel, on one page.")
	html.w(&b, `<section class="block lab"><div id="feed" class="lab-log" role="log" aria-label="Feed"></div>`)
	refetch(&b, key)
	html.w(&b, `</section>`)
	room_section(&b, room, tag)
	mp_panel(&b, tag, false)
	return strings.to_string(b)
}

blank_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Lab", "Blank", "A page for scripts that open their own sockets under this origin's CSP.")
	return strings.to_string(b)
}

@(private = "file")
refetch :: proc(b: ^strings.Builder, key: string) {
	html.w(b, `<div id="refetch" hx-get="/lab/feed?t=`)
	html.esc(b, key)
	html.w(b, `" hx-trigger="resync from:body"></div>`)
}

@(private = "file")
room_section :: proc(b: ^strings.Builder, room, tag: string) {
	html.w(b, `<section id="room" class="block lab" hx-ws:connect="/lab/ws/chat?room=`)
	html.esc(b, room)
	html.w(b, `&amp;tag=`)
	html.esc(b, tag)
	html.w(b, `&amp;hello=1"><p id="ws-status" class="muted"></p><div id="chat" class="lab-log" role="log" aria-label="Room"></div>`)
	html.w(b, `<form id="say" class="lab-say" hx-ws:send><label for="message">Message</label><textarea name="message" id="message" rows="2"></textarea><button id="send" class="btn btn-primary">Send</button></form></section>`)
}

@(private = "file")
mp_panel :: proc(b: ^strings.Builder, tag: string, count: bool) {
	html.w(b, `<section id="mp" class="block lab"><p><button id="build" class="btn" type="button" hx-get="/lab/multipart?n=3&amp;ms=300&amp;end_ms=1500" hx-target="#mp-default">Build</button> `)
	html.w(b, `<button id="slow" class="btn" type="button" hx-get="/lab/multipart?n=1&amp;ms=3000" hx-target="#mp-default">Slow</button></p>`)
	html.w(b, `<div id="mp-a"></div><div id="mp-b" class="lab-log" role="log" aria-label="Parts"></div><div id="mp-default"></div>`)
	if count {
		html.w(b, `<div id="counter" hx-multipart:connect="/lab/mp/count?n=2&amp;max=6&amp;tag=`)
		html.esc(b, tag)
		html.w(b, `" hx-multipart:close="mp-done"></div>`)
	}
	html.w(b, `<div id="counts" class="lab-log" role="log" aria-label="Counts"></div></section>`)
}

// ---- fragments ------------------------------------------------------------------------

// What a resync refetches: the topic it names, so a spec can see which.
refetched :: proc(key: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p class="refetched">refetched `)
	html.esc(&b, key)
	html.w(&b, `</p>`)
	return strings.to_string(b)
}

// One published line, appended to #feed out of band.
feed_item :: proc(id, text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<div hx-swap-oob="beforeend:#feed"><article id="m-`)
	html.esc(&b, id)
	html.w(&b, `">`)
	html.esc(&b, text)
	html.w(&b, `</article></div>`)
	return strings.to_string(b)
}

// One room message, appended to every socket's #chat out of band.
room_message :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<div id="chat" hx-swap-oob="beforeend"><p>`)
	html.esc(&b, text)
	html.w(&b, `</p></div>`)
	return strings.to_string(b)
}

tick :: proc(i: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<b>tick `)
	strings.write_int(&b, i)
	html.w(&b, `</b>`)
	return strings.to_string(b)
}

part :: proc(i, n: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p class="part" data-n="`)
	strings.write_int(&b, i)
	html.w(&b, `">part `)
	strings.write_int(&b, i)
	html.w(&b, ` of `)
	strings.write_int(&b, n)
	html.w(&b, `</p>`)
	return strings.to_string(b)
}

count :: proc(i: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<p id="c-`)
	strings.write_int(&b, i)
	html.w(&b, `" class="count">`)
	strings.write_int(&b, i)
	html.w(&b, `</p>`)
	return strings.to_string(b)
}

// The socket's greeting: a JSON envelope hx-ws routes to its target.
hello :: proc(n: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `{"content":"<span class=\"hello\">connected `)
	strings.write_int(&b, n)
	html.w(&b, `</span>","target":"#ws-status","swap":"innerHTML"}`)
	return strings.to_string(b)
}
