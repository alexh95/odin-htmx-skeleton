package obs

// ---- platform/obs: logs, metrics and health as data (L2) ------------------
//
// Supplies the data; platform/web serves it as /metrics, /livez, /readyz and
// /healthz (PLAN §10.4). Everything per request is per thread and lock-free:
//
//   - logs: logfmt, one line per event, into a 64 KiB buffer per event-loop
//     thread that flushes at 56 KiB, a second after the last flush, on drain and
//     from the crash handler (0.15-0.84 µs a line against 5.7-106 µs for a
//     log.infof line, 13 §5.1); other threads write each line through;
//   - request ids `<boot>-<loop>-<seq>`, made with no syscall and no lock;
//   - counters in a block per thread, summed on scrape with relaxed loads (6-50
//     ns per request against 97-121 ns for shared atomics, 13 §5.2);
//   - gauges, loop ticks, module health and declared limits, which their owners
//     push and readers only read.

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"
import "core:sync"

import "../sys"

Level :: log.Level

MAX_LOOPS :: 256
LINE_MAX :: 4096
BUF_SIZE :: 64 * 1024
FLUSH_AT :: 56 * 1024
FLUSH_EVERY_NS :: 1_000_000_000

@(private)
state: struct {
	level:     Level,
	boot_hex:  [8]byte, // the request id's first part: the boot time, so ids never repeat across restarts
	write_mu:  sync.Mutex, // whole buffers go out under it, so lines never interleave on a pipe
	out:       ^os.File,
	draining:  bool, // atomic
}

@(private)
Thread_Buf :: struct {
	data:       [BUF_SIZE]byte,
	n:          int,
	last_flush: i64,
}

@(private, thread_local) tl_buf: ^Thread_Buf // nil: write each line through
@(private, thread_local) tl_loop1: int // the loop index + 1: 0 is a thread with no loop
@(private, thread_local) tl_seq: u64
@(private, thread_local) tl_scratch: [LINE_MAX]byte
@(private, thread_local) tl_req: struct {
	id:     [32]byte,
	id_len: int,
	route1: u64, // Route + 1; 0 = none (a thread-local can't start at NO_ROUTE)
}

// Once, first thing in main. Lines below `level` are dropped where they're made.
init :: proc(level: Level) {
	state.level = level
	state.out = os.stderr
	_ = fmt.bprintf(state.boot_hex[:], "%08x", u32(sys.now_unix_ns() / 1e9))
}

level :: proc() -> Level { return state.level }

// An event-loop thread (F-4's on_thread_init): buffered logs, a loop index for
// request ids and the tick the watchdog reads.
thread_init :: proc(loop: int) {
	tl_loop1 = loop + 1
	tl_buf = new(Thread_Buf)
	tl_buf.last_flush = sys.mono_ns()
	if loop >= 0 && loop < MAX_LOOPS {
		for {
			n := sync.atomic_load(&loops)
			if n > loop { break }
			if _, ok := sync.atomic_compare_exchange_weak(&loops, n, loop + 1); ok { break }
		}
		tick(loop)
	}
	_ = counters_block()
}

// The loop's 1 s timer: flushes a buffer that has waited a second, and ticks.
thread_tick :: proc() {
	if tl_loop1 > 0 { tick(tl_loop1 - 1) }
	if tl_buf != nil && tl_buf.n > 0 && sys.mono_ns() - tl_buf.last_flush >= FLUSH_EVERY_NS {
		flush()
	}
}

// Writes this thread's buffered lines out: on drain, before exit, from the crash handler.
flush :: proc() {
	b := tl_buf
	if b == nil || b.n == 0 { return }
	write_out(b.data[:b.n])
	b.n = 0
	b.last_flush = sys.mono_ns()
}

@(private)
write_out :: proc(data: []byte) {
	sync.mutex_lock(&state.write_mu)
	_, _ = os.write(state.out, data)
	sync.mutex_unlock(&state.write_mu)
}

// ---- lines ----------------------------------------------------------------
//
//   ts=1792928474803 lvl=info mod=http ev=req id=4d48cf84-03-1a2b m=GET route=… st=200 us=183
//
//   if l, ok := obs.begin(.Info, "http", "req"); ok {
//       obs.str(&l, "route", route); obs.num(&l, "st", 200); obs.end(&l)
//   }
//
// A line is built in a fixed thread-local buffer, so making one allocates
// nothing; past LINE_MAX it is cut.

Line :: struct {
	b: strings.Builder,
}

level_name :: proc(l: Level) -> string {
	switch {
	case l >= .Fatal:   return "fatal"
	case l >= .Error:   return "error"
	case l >= .Warning: return "warn"
	case l >= .Info:    return "info"
	}
	return "debug"
}

begin :: proc(lvl: Level, mod, ev: string) -> (l: Line, ok: bool) {
	if lvl < state.level { return }
	l.b = strings.builder_from_bytes(tl_scratch[:])
	strings.write_string(&l.b, "ts=")
	strings.write_i64(&l.b, sys.now_unix_ns() / 1e6)
	strings.write_string(&l.b, " lvl=")
	strings.write_string(&l.b, level_name(lvl))
	str(&l, "mod", mod)
	if ev != "" { str(&l, "ev", ev) }
	return l, true
}

// A value with a space, a quote, an '=' or nothing in it is quoted.
str :: proc(l: ^Line, key, value: string) {
	strings.write_byte(&l.b, ' ')
	strings.write_string(&l.b, key)
	strings.write_byte(&l.b, '=')
	if !needs_quotes(value) {
		strings.write_string(&l.b, value)
		return
	}
	strings.write_byte(&l.b, '"')
	for i in 0 ..< len(value) {
		switch c := value[i]; c {
		case '"', '\\': strings.write_byte(&l.b, '\\'); strings.write_byte(&l.b, c)
		case '\n':      strings.write_string(&l.b, `\n`)
		case '\r':      strings.write_string(&l.b, `\r`)
		case '\t':      strings.write_string(&l.b, `\t`)
		case:
			if c < 0x20 || c == 0x7f { // a terminal escape, say, from a request line
				hex := "0123456789abcdef"
				strings.write_string(&l.b, `\x`)
				strings.write_byte(&l.b, hex[c >> 4])
				strings.write_byte(&l.b, hex[c & 0xf])
			} else {
				strings.write_byte(&l.b, c)
			}
		}
	}
	strings.write_byte(&l.b, '"')
}

num :: proc(l: ^Line, key: string, value: i64) {
	strings.write_byte(&l.b, ' ')
	strings.write_string(&l.b, key)
	strings.write_byte(&l.b, '=')
	strings.write_i64(&l.b, value)
}

end :: proc(l: ^Line) {
	strings.write_byte(&l.b, '\n')
	line := strings.to_string(l.b)
	if line[len(line) - 1] != '\n' { // cut at LINE_MAX: keep the line a line
		tl_scratch[LINE_MAX - 1] = '\n'
		line = string(tl_scratch[:])
	}
	b := tl_buf
	if b == nil {
		write_out(transmute([]byte)line)
		return
	}
	if b.n + len(line) > BUF_SIZE { flush() }
	copy(b.data[b.n:], line)
	b.n += len(line)
	if b.n >= FLUSH_AT { flush() }
}

@(private)
needs_quotes :: proc(s: string) -> bool {
	if s == "" { return true }
	for i in 0 ..< len(s) {
		switch c := s[i]; c {
		case ' ', '"', '=', '\\': return true
		case: if c < 0x20 || c == 0x7f { return true }
		}
	}
	return false
}

// core:log's procs (odin-http's own warnings, a feature's log.warnf) as logfmt
// lines: `mod=log msg="…" at=file:line`.
logger :: proc() -> log.Logger {
	return {procedure = logger_proc, lowest_level = state.level}
}

@(private)
logger_proc :: proc(data: rawptr, level: runtime.Logger_Level, text: string, options: runtime.Logger_Options, location := #caller_location) {
	l, ok := begin(level, "log", "")
	if !ok { return }
	str(&l, "msg", text)
	at := fmt.bprintf(tl_at[:], "%s:%d", file_base(location.file_path), location.line)
	str(&l, "at", at)
	end(&l)
}

@(private, thread_local) tl_at: [256]byte

@(private)
file_base :: proc(path: string) -> string {
	i := strings.last_index_any(path, `/\`)
	return path[i + 1:] if i >= 0 else path
}

// ---- request ids and routes ------------------------------------------------

// A route's handle: its counters, registered once per route row by app.check.
// A request counts into it, and a crash or a stall names it.
Route :: distinct u32
NO_ROUTE :: Route(max(u32))

@(private)
Route_Info :: struct {
	id:           string, // "GET /contacts/(%d+)"
	requests, us: Counter,
}

@(private) routes: [dynamic]Route_Info

register_route :: proc(id: string) -> Route {
	labels := strings.concatenate({`route="`, id, `"`})
	r := Route(len(routes))
	append(&routes, Route_Info{
		id       = id,
		requests = register_counter("app_http_requests_total", labels, "Requests answered, per route."),
		us       = register_counter("app_http_request_microseconds_total", labels, "Time in the app, per route, in microseconds."),
	})
	return r
}

route_id :: proc(r: Route) -> string {
	return routes[r].id if r != NO_ROUTE && int(r) < len(routes) else ""
}

count_request :: proc(r: Route, us: i64) {
	if r == NO_ROUTE { return }
	inc(routes[r].requests)
	inc(routes[r].us, u64(max(us, 0)))
}

// Each loop's current request, for the watchdog on another thread: atomic words
// only (a torn string read there could fault), resolved to text when it reports.
@(private) loop_req: [MAX_LOOPS]struct {
	seq:   u64,
	route: u64, // Route + 1; 0 = none
}

// `<boot>-<loop>-<seq>`, made the current request's id (what a crash names). A
// trusted proxy's X-Request-Id replaces it through set_request.
next_request_id :: proc() -> string {
	tl_seq += 1
	loop := tl_loop1 - 1 if tl_loop1 > 0 else 0xff
	s := format_id(tl_req.id[:], loop, tl_seq)
	tl_req.id_len = len(s)
	return s
}

// Into buf, which holds 28 bytes. By hand: fmt.bprintf cost about 1 % of a store
// write's CPU at one call per request (M1's parity profile).
@(private)
format_id :: proc(buf: []byte, loop: int, seq: u64) -> string {
	i := copy(buf, state.boot_hex[:])
	buf[i] = '-'
	i = put_hex(buf, i + 1, u64(loop), 2)
	buf[i] = '-'
	i = put_hex(buf, i + 1, seq)
	return string(buf[:i])
}

// v in lower-case hex, at least `width` digits, at buf[i:]; the index after it.
put_hex :: proc(buf: []byte, i: int, v: u64, width := 1) -> int {
	n := 1
	for x := v >> 4; x != 0; x >>= 4 { n += 1 }
	n = max(n, width)
	v := v
	digits := "0123456789abcdef"
	for k := i + n - 1; k >= i; k -= 1 {
		buf[k] = digits[v & 0xf]
		v >>= 4
	}
	return i + n
}

// The request this thread serves now.
set_request :: proc(id: string, route: Route) {
	if raw_data(id) != raw_data(tl_req.id[:]) {
		tl_req.id_len = copy(tl_req.id[:], id)
	}
	tl_req.route1 = u64(route) + 1 if route != NO_ROUTE else 0
	if l := tl_loop1 - 1; l >= 0 && l < MAX_LOOPS {
		sync.atomic_store_explicit(&loop_req[l].seq, tl_seq, .Relaxed)
		sync.atomic_store_explicit(&loop_req[l].route, tl_req.route1, .Relaxed)
	}
}

clear_request :: proc() {
	tl_req.id_len = 0
	tl_req.route1 = 0
	if l := tl_loop1 - 1; l >= 0 && l < MAX_LOOPS {
		sync.atomic_store_explicit(&loop_req[l].route, 0, .Relaxed)
	}
}

current_request :: proc() -> (id: string, route: string) {
	return string(tl_req.id[:tl_req.id_len]), route_id(Route(tl_req.route1 - 1)) if tl_req.route1 != 0 else ""
}

// What `loop` was serving, as the watchdog reports it: the generated id (a proxy's
// id isn't kept per loop) and the route, "" when idle.
loop_request :: proc(loop: int, buf: []byte) -> (id: string, route: string) {
	seq := sync.atomic_load_explicit(&loop_req[loop].seq, .Relaxed)
	r := sync.atomic_load_explicit(&loop_req[loop].route, .Relaxed)
	if r == 0 { return "", "" }
	return format_id(buf, loop, seq), route_id(Route(r - 1))
}

// -1 on a thread with no event loop.
current_loop :: proc() -> int { return tl_loop1 - 1 }

// ---- draining -------------------------------------------------------------

set_draining :: proc() { sync.atomic_store(&state.draining, true) }
is_draining :: proc() -> bool { return sync.atomic_load(&state.draining) }
