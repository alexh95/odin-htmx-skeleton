package obs

import "base:runtime"
import "core:strings"
import "core:testing"
import "core:thread"

@(private = "file")
buffered :: proc() -> string {
	return string(tl_buf.data[:tl_buf.n])
}

// One test, in order: the registries are process-wide.
@(test)
lines_ids_counters_and_health :: proc(t: ^testing.T) {
	context.allocator = runtime.heap_allocator() // boot-time registrations, as in main
	init(.Info)
	thread_init(0)
	defer { free(tl_buf); tl_buf = nil }

	// logfmt: values that need it are quoted and escaped; below the floor, nothing.
	if l, ok := begin(.Info, "http", "req"); ok {
		str(&l, "route", "GET /data")
		str(&l, "m", "GET")
		str(&l, "q", `a"b=c`)
		str(&l, "empty", "")
		str(&l, "esc", "a\x1b[2Jb\x7f")
		str(&l, "c1", "\u009b2J\xff é")
		num(&l, "st", 200)
		end(&l)
	}
	_, below := begin(.Debug, "http", "req")
	testing.expect(t, !below)
	line := buffered()
	testing.expect(t, strings.has_prefix(line, "ts="), line)
	testing.expect(t, strings.has_suffix(line, ` lvl=info mod=http ev=req route="GET /data" m=GET q="a\"b=c" empty="" esc="a\x1b[2Jb\x7f" c1="\xc2\x9b2J\xff é" st=200`+"\n"), line)
	tl_buf.n = 0

	// Request ids: <boot>-<loop>-<seq>, the seq per thread.
	a := strings.clone(next_request_id(), context.temp_allocator)
	b := next_request_id()
	testing.expect_value(t, len(a), len("12345678-00-1"))
	testing.expect(t, strings.has_suffix(a, "-00-1") && strings.has_suffix(b, "-00-2"), b)

	// Counters from several threads sum on the scrape.
	c := register_counter("test_total", "", "A test counter.")
	r := register_route("GET /x")
	inc(c)
	count_request(r, 120)
	worker :: proc(c: Counter) {
		for _ in 0 ..< 1000 { inc(c) }
	}
	threads: [4]^thread.Thread
	for &th in threads { th = thread.create_and_start_with_poly_data(c, worker) }
	for th in threads { thread.join(th); thread.destroy(th) }
	testing.expect_value(t, counter_value(c), 4001)

	set_request(next_request_id(), r)
	id, route := current_request()
	testing.expect_value(t, route, "GET /x")
	testing.expect(t, strings.has_suffix(id, "-00-3"), id)
	clear_request()

	sb := strings.builder_make(context.temp_allocator)
	render(&sb)
	out := strings.to_string(sb)
	testing.expect(t, strings.contains(out, "# TYPE test_total counter\ntest_total 4001\n"), out)
	testing.expect(t, strings.contains(out, `app_http_requests_total{route="GET /x"} 1`), out)
	testing.expect(t, strings.contains(out, `app_http_request_microseconds_total{route="GET /x"} 120`), out)
	testing.expect(t, strings.contains(out, `app_loop_tick_age_seconds{loop="0"}`), out)

	// Readiness: a critical module down fails it, a degraded optional one doesn't.
	set_health("store", .Ok, critical = true)
	set_health("llama", .Degraded, "no answer in 2 s")
	ok, _ := ready()
	testing.expect(t, ok)
	set_health("store", .Down, "locked")
	ok2, why := ready()
	testing.expect(t, !ok2 && why == "store")
	set_health("store", .Ok)
	set_draining()
	ok3, why3 := ready()
	testing.expect(t, !ok3 && why3 == "draining")
}
