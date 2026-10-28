package status

// ---- status: the domain (PLAN §15.4, D36) -------------------------------------------------
//
// What the status page shows, one probe a line: every module's health as it pushed it to obs
// (§10.4), whether every event loop still ticks, the process itself, and the STATUS_PROBES
// externals: the lab's witness board (M3) is the other witnesses' /healthz, each probed every
// WATCH_EVERY by a thread of its own with a 2 s socket timeout. M5 adds llama, the Pi agent,
// disk and backups to the same list.

import "core:fmt"
import "core:hash"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "../../platform/env"
import "../../platform/obs"
import "../../platform/sys"

ENV := [?]env.Row {
	{name = "STATUS_PROBES", kind = .String, doc = "external probes: name=host:port, comma-separated (the lab's witnesses: their /healthz)"},
}

WATCH_EVERY :: 10 * time.Second
PROBE_TIMEOUT :: 2 * time.Second

// A loop that hasn't ticked for this long is stuck (/livez says the same at 30 s, and the
// watchdog exits at 10 s: past 2 s the page already says something is wrong).
STUCK :: 2 * time.Second

Probe :: struct {
	name, state, message: string,
	public:               bool, // an external's message (its version, its time) is what it answers anyone
}

// An external probe and what it last said; `message` lives on the heap, owned by the watcher.
External :: struct {
	name, host: string,
	state:      string,
	message:    string,
}

@(private)
externals: struct {
	mu:   sync.Mutex,
	list: [dynamic]External,
}

@(private)
started_ns: i64

init :: proc() {
	started_ns = sys.mono_ns()
	env.record("", ENV[:])
	externals.list = parse_probes(env.str("STATUS_PROBES"))
	if len(externals.list) > 0 { thread.create_and_start(watch, self_cleanup = true) }
}

// `name=host:port,…`: a name is lower-case letters, digits and dashes (it becomes an element
// id); a malformed entry is skipped, and so said on stderr by the caller's env dump.
parse_probes :: proc(s: string) -> [dynamic]External {
	out := make([dynamic]External)
	rest := s
	for item in strings.split_iterator(&rest, ",") {
		eq := strings.index_byte(item, '=')
		if eq <= 0 { continue }
		name, host := strings.trim_space(item[:eq]), strings.trim_space(item[eq + 1:])
		if !is_name(name) || strings.index_byte(host, ':') <= 0 { continue }
		append(&out, External{name = strings.clone(name), host = strings.clone(host), state = "checking"})
	}
	return out
}

@(private)
is_name :: proc(s: string) -> bool {
	if s == "" { return false }
	for c in transmute([]byte)s {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') { return false }
	}
	return true
}

@(private)
watch :: proc() {
	for {
		for i in 0 ..< len(externals.list) {
			state, message := probe(externals.list[i].host)
			sync.mutex_lock(&externals.mu)
			e := &externals.list[i]
			delete(e.message)
			e.state, e.message = state, message
			sync.mutex_unlock(&externals.mu)
		}
		time.sleep(WATCH_EVERY)
	}
}

// GET /healthz on `host` (host:port), blocking on this thread: "ok" with the witness's version
// and time, or "down" and why. The message is heap-allocated for the board.
probe :: proc(host: string) -> (state, message: string) {
	t0 := time.tick_now()
	ep, rerr := net.resolve_ip4(host)
	if rerr != nil { return "down", fmt.aprintf("%s doesn't resolve", host) }
	sock, derr := net.dial_tcp(ep)
	if derr != nil { return "down", fmt.aprintf("%s refused the connection", host) }
	defer net.close(sock)
	net.set_option(sock, .Receive_Timeout, PROBE_TIMEOUT)
	net.set_option(sock, .Send_Timeout, PROBE_TIMEOUT)
	req := fmt.tprintf("GET /healthz HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n", host)
	if _, err := net.send_tcp(sock, transmute([]byte)req); err != nil { return "down", fmt.aprintf("%s: the request didn't go out", host) }
	buf: [2048]byte
	n := 0
	for n < len(buf) {
		got, err := net.recv_tcp(sock, buf[n:])
		if err != nil || got == 0 { break }
		n += got
	}
	head := string(buf[:n])
	ms := time.duration_milliseconds(time.tick_since(t0))
	if !strings.has_prefix(head, "HTTP/1.1 200 ") {
		if n == 0 { return "down", fmt.aprintf("no answer in %.0f ms", ms) }
		line, _, _ := strings.partition(head, "\r\n")
		return "down", fmt.aprintf("%s", line)
	}
	version := "?"
	lines := head
	for line in strings.split_lines_iterator(&lines) {
		if len(line) > 11 && strings.equal_fold(line[:10], "x-version:") { version = strings.trim_space(line[10:]); break }
	}
	return "ok", fmt.aprintf("version %s, %.0f ms", version, ms)
}

board :: proc(version: string, out: ^[dynamic]Probe) {
	for h in obs.modules() { append(out, Probe{h.module, obs.STATE_NAMES[h.state], h.message, false}) }
	loop, age := obs.oldest_tick()
	if age > i64(STUCK) {
		append(out, Probe{"loops", "down", fmt.tprintf("loop %d last ticked %d ms ago", loop, age / 1e6), false})
	} else {
		append(out, Probe{"loops", "ok", fmt.tprintf("%d ticking", obs.loops), false})
	}
	up := time.Duration(sys.mono_ns() - started_ns)
	append(out, Probe{"process", "ok", fmt.tprintf("up %s, version %s", uptime(up), version), false})
	sync.mutex_lock(&externals.mu)
	for e in externals.list {
		append(out, Probe{e.name, e.state, strings.clone(e.message, context.temp_allocator), true})
	}
	sync.mutex_unlock(&externals.mu)
}

// The board's tag for a poll: the states alone, so a message that changes (the uptime) is no
// reason to send the board again.
tag :: proc(probes: []Probe) -> u64 {
	h: u64 = 14695981039346656037
	for p in probes {
		h = hash.fnv64a(transmute([]byte)p.name, h)
		h = hash.fnv64a(transmute([]byte)p.state, h)
	}
	return h
}

@(private)
uptime :: proc(d: time.Duration) -> string {
	s := int(d / time.Second)
	switch {
	case s < 60:    return fmt.tprintf("%d s", s)
	case s < 3600:  return fmt.tprintf("%d min", s / 60)
	case s < 86400: return fmt.tprintf("%d h %d min", s / 3600, s % 3600 / 60)
	}
	return fmt.tprintf("%d d %d h", s / 86400, s % 86400 / 3600)
}
