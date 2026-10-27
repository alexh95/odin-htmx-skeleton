package scripting_views

// ---- scripting: the nonce class's pages (PLAN §12.2, §12.3, §15.5) -----------------------
//
// Every page here is on the Scripting bundle (hx-csp in front of htmx, hx-live,
// the stream extensions) under a nonce CSP with no 'self'. hx-csp strips the hx-*
// attributes of any element whose hx-nonce isn't the page's, so every htmx
// element carries `hx-nonce="<%N%>"` (html.NONCE_MARK), which the response
// writer turns into this response's nonce; a fragment's own nonce is rewritten to
// the page's by hx-csp when it arrives. Under that gate an element may carry code
// (hx-on, a trigger filter, js: values, hx-live), which the hash CSP refuses.

import "core:strings"

import "../../../platform/html"

@(private = "file")
N :: html.NONCE_MARK

// The section of links the index ends with, and each page's way back.
@(private = "file")
card :: proc(b: ^strings.Builder, href, title, text: string) {
	html.w(b, `<a class="card scripting-card" href="`)
	html.w(b, href)
	html.w(b, `"><h2>`)
	html.esc(b, title)
	html.w(b, `</h2><p class="muted">`)
	html.esc(b, text)
	html.w(b, `</p></a>`)
}

index_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Scripting", "The nonce class", "A nonce per response, hx-csp in front of htmx, and code in markup only on elements that carry the nonce.")
	html.w(&b, `<section class="block scripting-prose"><p>The rest of the site runs under a hash CSP: scripts from this origin plus one hashed inline script, and no eval, so <code>hx-on</code>, trigger filters, <code>js:</code> values and hx-live do nothing there. These pages load their own bundle, with hx-csp first, under <code>script-src 'nonce-…'</code> and nothing else. The server stamps that response's nonce on every htmx element; hx-csp strips the htmx attributes of an element without it, and runs code only for an element that carries it.</p></section>`)
	html.w(&b, `<section class="block"><div class="scripting-grid">`)

	html.w(&b, `<div class="card scripting-demo"><h2>A nonced hx-get</h2><p class="muted">Its answer carries that response's own nonce, which hx-csp rewrites to the page's: the button inside it works too.</p>`)
	html.w(&b, `<button id="get-nonced" class="btn" type="button" hx-get="/scripting/hello?v=nonced" hx-target="#out-get" hx-nonce="`+N+`">Fetch</button><div id="out-get" class="scripting-out" aria-live="polite"></div></div>`)

	html.w(&b, `<div class="card scripting-demo"><h2>hx-on</h2><p class="muted">An inline handler, run through a nonced script rather than eval.</p>`)
	html.w(&b, `<button id="on-click" class="btn" type="button" hx-on:click="this.textContent = 'hx-on ran'" hx-nonce="`+N+`">Click</button></div>`)

	html.w(&b, `<div class="card scripting-demo"><h2>A trigger filter</h2><p class="muted">The request goes only when the expression holds: here, unless Alt is down.</p>`)
	html.w(&b, `<button id="filtered" class="btn" type="button" hx-get="/scripting/hello?v=filtered" hx-trigger="click[!event.altKey]" hx-target="#out-filter" hx-nonce="`+N+`">Click</button><div id="out-filter" class="scripting-out" aria-live="polite"></div></div>`)

	html.w(&b, `<div class="card scripting-demo"><h2>A js: value</h2><p class="muted">The parameter is computed in the browser when the request goes.</p>`)
	html.w(&b, `<button id="js-vals" class="btn" type="button" hx-get="/scripting/hello" hx-vals="js:{v: 'js-' + (6 * 7)}" hx-target="#out-js" hx-nonce="`+N+`">Send</button><div id="out-js" class="scripting-out" aria-live="polite"></div></div>`)

	html.w(&b, `</div></section><section class="block"><div class="scripting-cards">`)
	card(&b, "/scripting/live", "hx-live", "One password-rules widget built three ways: plain JavaScript, a hyperscript behaviour and hx-live bindings.")
	card(&b, "/scripting/streams", "Streams under hx-csp", "Where the gate holds and where it doesn't: SSE, WebSocket and multipart fragments, nonced, unnonced and delegated.")
	card(&b, "/scripting/tt", "Trusted Types", "The same class with Trusted Types enforced: htmx and hx-live keep working, and the page loads no hyperscript.")
	html.w(&b, `</div></section>`)
	return strings.to_string(b)
}

// GET /scripting/hello?v=<key>: what a demo fetches. The answer carries a nonced
// button of its own, which works only because hx-csp rewrites this response's
// nonce to the page's (11 §2.2's "normal hx-get fragment").
hello :: proc(v: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<span class="scripting-hello" id="hello-`)
	html.esc(&b, v)
	html.w(&b, `">hello-`)
	html.esc(&b, v)
	html.w(&b, `</span>`)
	if !strings.has_suffix(v, "-again") && len(v) <= 30 {
		html.w(&b, ` <button class="btn btn-ghost" type="button" id="again-`)
		html.esc(&b, v)
		html.w(&b, `" hx-get="/scripting/hello?v=`)
		html.esc(&b, v)
		html.w(&b, `-again" hx-target="this" hx-swap="outerHTML" hx-nonce="`+N+`">again</button>`)
	}
	return strings.to_string(b)
}

// ---- /scripting/live -------------------------------------------------------------------

// What POST /scripting/score answers: the score hs-include sent, or that none came.
score :: proc(n: int, ok: bool) -> string {
	b := strings.builder_make(context.temp_allocator)
	html.w(&b, `<span id="pw-hs-heard">`)
	if ok {
		html.w(&b, `The server heard `)
		strings.write_int(&b, n)
		html.w(&b, ` of 4.`)
	} else {
		html.w(&b, `The server heard no score.`)
	}
	html.w(&b, `</span>`)
	return strings.to_string(b)
}

// The same widget three ways (§12.3): four rules ticked as the password is typed,
// and a score. The plain-JS card is scripting.js's (app.js), the hyperscript card
// the PasswordRules behaviour (inert on the vanilla client), and the hx-live card
// nothing but bindings in its markup.
live_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Scripting", "hx-live", "One widget three ways: plain JavaScript in app.js, a hyperscript behaviour, and hx-live bindings that run only under the nonce.")
	html.w(&b, `<section class="block"><div class="scripting-grid">`)

	html.w(&b, `<div class="card scripting-pw" id="pw-js-card" data-pw-rules><h2>app.js</h2>`)
	field(&b, "pw-js")
	html.w(&b, `<ul class="scripting-pw-list">`)
	rule(&b, "len", "12 characters or more")
	rule(&b, "digit", "a digit")
	rule(&b, "mixed", "upper and lower case")
	rule(&b, "word", "not the word “password”")
	html.w(&b, `</ul><p class="scripting-pw-score" aria-live="polite">0 of 4</p></div>`)

	html.w(&b, `<div class="card scripting-pw" id="pw-hs-card"`)
	html.behave(&b, .Password_Rules)
	html.w(&b, `><h2>hyperscript</h2>`)
	field(&b, "pw-hs")
	html.w(&b, `<ul class="scripting-pw-list">`)
	rule(&b, "len", "12 characters or more")
	rule(&b, "digit", "a digit")
	rule(&b, "mixed", "upper and lower case")
	rule(&b, "word", "not the word “password”")
	html.w(&b, `</ul><p class="scripting-pw-score" aria-live="polite">0 of 4</p>`)
	// hs-include adds the behaviour's :score to the request (^: from an ancestor's
	// element scope), so the server sees what hyperscript computed.
	html.w(&b, `<button class="btn" type="button" id="pw-hs-ask" hx-post="/scripting/score" hs-include="^score" hx-target="#pw-hs-said" hx-nonce="`+N+`">Tell the server</button>`)
	html.w(&b, `<p id="pw-hs-said" class="scripting-out" aria-live="polite"></p></div>`)

	// hx-live reads the field through q() on every input; each binding is code, so
	// each element carries the nonce. The score counts the ticks above it, which
	// hx-live computes first (document order).
	html.w(&b, `<div class="card scripting-pw" id="pw-live-card"><h2>hx-live</h2>`)
	field(&b, "pw-live")
	html.w(&b, `<ul class="scripting-pw-list" id="pw-live-rules">`)
	html.w(&b, `<li data-rule="len" hx-nonce="`+N+`" :.ok="q('#pw-live').value.length >= 12">12 characters or more</li>`)
	html.w(&b, `<li data-rule="digit" hx-nonce="`+N+`" :.ok="/[0-9]/.test(q('#pw-live').value)">a digit</li>`)
	html.w(&b, `<li data-rule="mixed" hx-nonce="`+N+`" :.ok="/[a-z]/.test(q('#pw-live').value) &amp;&amp; /[A-Z]/.test(q('#pw-live').value)">upper and lower case</li>`)
	html.w(&b, `<li data-rule="word" hx-nonce="`+N+`" :.ok="q('#pw-live').value !== '' &amp;&amp; !/password/i.test(q('#pw-live').value)">not the word “password”</li>`)
	html.w(&b, `</ul><p class="scripting-pw-score" aria-live="polite" hx-nonce="`+N+`" :text="q('#pw-live-rules li.ok').count + ' of 4'">0 of 4</p></div>`)

	html.w(&b, `</div></section>`)
	back(&b)
	return strings.to_string(b)
}

@(private = "file")
field :: proc(b: ^strings.Builder, id: string) {
	html.w(b, `<label class="field"><span>Password</span><input type="password" autocomplete="new-password" id="`)
	html.w(b, id)
	html.w(b, `"></label>`)
}

@(private = "file")
rule :: proc(b: ^strings.Builder, key, text: string) {
	html.w(b, `<li data-rule="`)
	html.w(b, key)
	html.w(b, `">`)
	html.esc(b, text)
	html.w(b, `</li>`)
}

@(private = "file")
back :: proc(b: ^strings.Builder) {
	html.w(b, `<p class="block"><a href="/scripting">Back to the nonce class</a></p>`)
}

// ---- /scripting/streams ----------------------------------------------------------------

// Research 11 §2.2's matrix on the real streams: hx-csp gates only what htmx core
// initialises, and promotes a fragment's nonce only after a request, so a streamed
// fragment's hx-* works only with the page's own nonce, which the page sends in
// the connect URL (`pn`) for the server to stamp, or by delegation to a nonced
// ancestor. Its gaps are pinned by streams-hxcsp.spec, so an upstream fix shows up
// as a spec diff.
streams_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Scripting", "Streams under hx-csp", "Fragments from SSE, a WebSocket and multipart parts: each carries four buttons, and only the page's nonce or delegation makes one work.")
	html.w(&b, `<section class="block scripting-prose"><p>Each stream sends the same four buttons: one with no nonce, one with the stream response's own nonce, one with the page's nonce (sent to the server in the connect URL), and a plain button that a nonced ancestor handles by <code>hx-trigger="click target:.act"</code>. hx-csp strips the first two. It also never gates <code>hx-sse:connect</code> or <code>hx-ws:connect</code>: an injected, unnonced one connects. That is why the rest of the site keeps the hash CSP and doesn't stream under hx-csp.</p></section>`)
	zone(&b, "sse", "SSE", `<div id="sse-box" class="scripting-box" hx-sse:connect="/scripting/streams/sse?pn=`+N+`" hx-nonce="`+N+`"></div>`)
	zone(&b, "ws", "WebSocket", `<div id="ws-box" class="scripting-box" hx-ws:connect="/scripting/streams/ws?pn=`+N+`" hx-nonce="`+N+`"></div>`)
	zone(&b, "mp", "Multipart", `<div id="mp-box" class="scripting-box" hx-get="/scripting/streams/mp?pn=`+N+`" hx-trigger="load" hx-nonce="`+N+`"></div>`)
	back(&b)
	return strings.to_string(b)
}

// One transport's panel: its box inside the nonced ancestor that handles the
// delegated button, and the slot every button's answer lands in.
@(private = "file")
zone :: proc(b: ^strings.Builder, t, title, box: string) {
	html.w(b, `<section class="block scripting-panel"><h2>`)
	html.w(b, title)
	html.w(b, `</h2><div id="`)
	html.w(b, t)
	html.w(b, `-zone" hx-get="/scripting/hello?v=`)
	html.w(b, t)
	html.w(b, `-delegated" hx-trigger="click target:.act" hx-target="#`)
	html.w(b, t)
	html.w(b, `-out" hx-nonce="`+N+`">`)
	html.w(b, box)
	html.w(b, `</div><div id="`)
	html.w(b, t)
	html.w(b, `-out" class="scripting-out" aria-live="polite"></div></section>`)
}

// The four buttons a stream sends for transport `t`: no nonce, the stream
// response's own (`own`), the page's (`page`, as the connect URL carried it), and
// a plain one for the ancestor's delegation. Values are checked by the web
// package (`t` is fixed; both nonces base64url) and escaped anyway.
stream_buttons :: proc(t, own, page: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	button :: proc(b: ^strings.Builder, t, kind, label, nonce: string, stamp: bool) {
		html.w(b, `<button class="btn" type="button" id="`)
		html.w(b, t)
		html.w(b, `-`)
		html.w(b, kind)
		html.w(b, `" hx-get="/scripting/hello?v=`)
		html.w(b, t)
		html.w(b, `-`)
		html.w(b, kind)
		html.w(b, `" hx-target="#`)
		html.w(b, t)
		html.w(b, `-out"`)
		if stamp {
			html.w(b, ` hx-nonce="`)
			html.esc(b, nonce)
			html.w(b, `"`)
		}
		html.w(b, `>`)
		html.w(b, label)
		html.w(b, `</button> `)
	}
	button(&b, t, "none", "no nonce", "", false)
	button(&b, t, "own", "its own nonce", own, true)
	button(&b, t, "page", "the page's nonce", page, true)
	html.w(&b, `<button class="btn act" type="button" id="`)
	html.w(&b, t)
	html.w(&b, `-act">delegated</button>`)
	return strings.to_string(b)
}

// ---- /scripting/tt ---------------------------------------------------------------------

// Trusted Types enforced: only hx-csp's `htmx` policy may write a DOM sink. htmx's
// swaps and hx-live's bindings go through it; hyperscript's `put` has no policy,
// so this page loads none (11 §2.3).
tt_page :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	html.page_head(&b, "Scripting", "Trusted Types", "require-trusted-types-for 'script' with hx-csp's htmx policy: swaps and bindings work, and no hyperscript loads.")
	html.w(&b, `<section class="block"><div class="scripting-grid">`)
	html.w(&b, `<div class="card scripting-demo"><h2>A swap</h2><p class="muted">htmx writes the answer through the htmx policy.</p>`)
	html.w(&b, `<button id="tt-get" class="btn" type="button" hx-get="/scripting/hello?v=tt" hx-target="#tt-out" hx-nonce="`+N+`">Fetch</button><div id="tt-out" class="scripting-out" aria-live="polite"></div></div>`)
	html.w(&b, `<div class="card scripting-demo"><h2>A binding</h2><label class="field"><span>Type</span><input id="tt-in" type="text"></label>`)
	html.w(&b, `<p id="tt-count" class="scripting-out" hx-nonce="`+N+`" :text="q('#tt-in').value.length + ' characters'">0 characters</p></div>`)
	html.w(&b, `</div></section>`)
	back(&b)
	return strings.to_string(b)
}
