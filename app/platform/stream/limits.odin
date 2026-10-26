package stream

// ---- admission (§9.4) -------------------------------------------------------------
//
// Before any stream begins: 503 past a stream cap or the queued-bytes cap, 429
// with Retry-After past STREAM_CONNECTS a minute from one client. The counts
// cover every stream (SSE, a socket, a multipart feed), whatever opened it.

import "core:hash"
import "core:net"
import "core:strconv"
import "core:sync"
import "core:time"

import "../env"
import "../guard"
import "../obs"
import "../sys"
import "../web"

ENV := [?]env.Row {
	{name = "STREAM_HEARTBEAT_S", kind = .Int, def = "20", doc = "seconds between heartbeats (SSE comment, WS ping), under the proxies' idle cuts"},
	{name = "STREAM_MAX_QUEUED", kind = .Size, def = "256KiB", doc = "bytes queued to one stream before it is closed as too slow (WS: 1013)"},
	{name = "STREAMS_TOTAL", kind = .Int, def = "8192", doc = "open streams in all (at most MAX_CONNS); 503 past it"},
	{name = "STREAMS_PER_USER", kind = .Int, def = "8", doc = "open streams per signed-in member; 503 past it"},
	{name = "STREAMS_PER_CLIENT", kind = .Int, def = "16", doc = "open streams per client address; 503 past it"},
	{name = "STREAM_CONNECTS", kind = .Int, def = "20", doc = "streams one client may open a minute; 429 past it"},
	{name = "STREAM_QUEUED_TOTAL", kind = .Size, def = "64MiB", doc = "bytes waiting for all streams' peers; new streams get 503 past it"},
}

@(private)
lim := struct {
	total, per_user, per_client, connects, queued, max_queued: int,
	heartbeat: time.Duration,
} {8192, 8, 16, 20, 64 << 20, web.STREAM_MAX_QUEUED, 20 * time.Second}

// Records the rows before app.check, so --limits prints them; a profile that
// streams calls it through hub.init.
init :: proc() {
	@(static) done: bool
	if done { return }
	done = true
	env.record("", ENV[:])
	lim.total = env.int_("STREAMS_TOTAL")
	lim.per_user = env.int_("STREAMS_PER_USER")
	lim.per_client = env.int_("STREAMS_PER_CLIENT")
	lim.connects = env.int_("STREAM_CONNECTS")
	lim.queued = env.size("STREAM_QUEUED_TOTAL")
	lim.max_queued = max(4096, env.size("STREAM_MAX_QUEUED"))
	lim.heartbeat = time.Duration(max(1, env.int_("STREAM_HEARTBEAT_S"))) * time.Second
	obs.limit("stream", "heartbeat", i64(lim.heartbeat / time.Second), "s")
	obs.limit("stream", "ws_pong_deadline", i64(WS_PONG_DEADLINE / time.Second), "s")
	obs.limit("stream", "total", i64(lim.total))
	obs.limit("stream", "per_user", i64(lim.per_user))
	obs.limit("stream", "per_client", i64(lim.per_client))
	obs.limit("stream", "connects_per_minute", i64(lim.connects))
	obs.limit("stream", "queued_total", i64(lim.queued), "B")
	obs.limit("stream", "queued_per_stream", i64(lim.max_queued), "B")
}

@(private)
Client_Count :: struct {
	open:     int,
	minute:   i64, // the minute `connects` counts
	connects: int,
}

@(private)
adm: struct {
	mu:      guard.Mutex,
	open:    int,
	clients: map[u64]Client_Count,
	users:   map[u64]int,
	loops:   [dynamic]^Loop_Stat, // every loop that has had a stream
}

// One per loop that has had a stream: what its streams have queued, summed on
// each heartbeat and after each hub drain.
@(private)
Loop_Stat :: struct {
	queued: int, // atomic
}

// Takes a stream slot for the request in front's context, or answers 503 or 429
// and returns false.
@(private)
admit :: proc(res: ^web.Response) -> (client, user: u64, ok: bool) {
	c := web.ctx()
	client = client_key(c.client)
	user = c.viewer.id
	minute := sys.mono_ns() / 60e9
	queued := queued_total()

	guard.lock(&adm.mu)
	if adm.clients == nil {
		adm.clients = make(map[u64]Client_Count, heap())
		adm.users = make(map[u64]int, heap())
	}
	if len(adm.clients) > 4096 { sweep_clients(minute) }
	cl := adm.clients[client]
	if cl.minute != minute { cl.minute, cl.connects = minute, 0 }
	cl.connects += 1
	status := web.Status.OK
	switch {
	case cl.connects > lim.connects:
		status = .Too_Many_Requests
	case adm.open >= lim.total, cl.open >= lim.per_client, user != 0 && adm.users[user] >= lim.per_user, queued > lim.queued:
		status = .Service_Unavailable
	}
	if status == .OK {
		cl.open += 1
		adm.open += 1
		if user != 0 { adm.users[user] += 1 }
	}
	adm.clients[client] = cl
	guard.unlock(&adm.mu)

	if status == .OK { return client, user, true }
	retry: [8]byte
	secs := 60 - (sys.mono_ns() / 1e9) % 60 if status == .Too_Many_Requests else 5
	web.set_header(res, "retry-after", strconv.write_int(retry[:], secs, 10))
	web.respond_status(res, status)
	return client, user, false
}

@(private)
release :: proc(c: ^Conn) {
	guard.lock(&adm.mu)
	adm.open -= 1
	if cl, found := &adm.clients[c.client]; found { cl.open -= 1 }
	if c.member != 0 {
		if n := adm.users[c.member]; n <= 1 { delete_key(&adm.users, c.member) } else { adm.users[c.member] = n - 1 }
	}
	guard.unlock(&adm.mu)
}

// Under adm.mu: clients with nothing open and no connect this minute.
@(private)
sweep_clients :: proc(minute: i64) {
	for k, v in adm.clients {
		if v.open == 0 && v.minute != minute { delete_key(&adm.clients, k) }
	}
}

// The address as a map key; the address itself is never kept.
client_key :: proc(a: net.Address) -> u64 {
	switch v in a {
	case net.IP4_Address:
		b := v
		return hash.fnv64a(b[:])
	case net.IP6_Address:
		b := transmute([16]u8)v
		return hash.fnv64a(b[:])
	}
	return 0
}

// What every loop's streams have queued, as last summed.
queued_total :: proc() -> (n: int) {
	guard.lock(&adm.mu)
	for l in adm.loops { n += sync.atomic_load(&l.queued) }
	guard.unlock(&adm.mu)
	return
}

// Sums this loop's queued bytes; the hub calls it after each drain.
refresh_queued :: proc() {
	if here.stat == nil { return }
	n := 0
	for c in here.conns { n += web.stream_queued(c.s) }
	sync.atomic_store(&here.stat.queued, n)
}

// How many streams are open in all.
open_total :: proc() -> int {
	guard.lock(&adm.mu)
	defer guard.unlock(&adm.mu)
	return adm.open
}
