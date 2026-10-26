package obs

// ---- metrics --------------------------------------------------------------
//
// Registered at boot, before the loops start (app.check registers each route's
// pair, a feature's init its own), then only counted and read. A counter is an
// index into each thread's block: `inc` is one thread-local add. A scrape sums
// the blocks with relaxed atomic loads, so it reads every thread's count as of
// some recent moment, which is all a counter promises. Gauges are pushed values.

import "core:fmt"
import "core:strings"
import "core:sync"

import "../sys"

MAX_COUNTERS :: 2048
MAX_GAUGES :: 256
MAX_THREADS :: 512

Kind :: enum u8 {
	Counter,
	Gauge,
}

Counter :: distinct u32
Gauge :: distinct u32

@(private)
Metric :: struct {
	name, labels, help: string, // labels: `route="GET /data"`, or ""
	kind:               Kind,
	index:              u32,
}

@(private)
Block :: struct {
	v: [MAX_COUNTERS]u64,
}

@(private)
reg: struct {
	metrics:   [dynamic]Metric,
	counters:  u32,
	gauges:    u32,
	blocks_mu: sync.Mutex,
	blocks:    [MAX_THREADS]^Block,
	nblocks:   int, // atomic
	gauge:     [MAX_GAUGES]i64, // atomic
}

@(private, thread_local) tl_block: ^Block

loops: int // atomic: how many event loops have started (their indexes are 0 ..< loops)
@(private) loop_ticks: [MAX_LOOPS]i64 // atomic: mono ns of each loop's last tick

register_counter :: proc(name, labels, help: string) -> Counter {
	assert(reg.counters < MAX_COUNTERS, "obs: too many counters")
	c := Counter(reg.counters)
	reg.counters += 1
	append(&reg.metrics, Metric{name, labels, help, .Counter, u32(c)})
	return c
}

register_gauge :: proc(name, labels, help: string) -> Gauge {
	assert(reg.gauges < MAX_GAUGES, "obs: too many gauges")
	g := Gauge(reg.gauges)
	reg.gauges += 1
	append(&reg.metrics, Metric{name, labels, help, .Gauge, u32(g)})
	return g
}

inc :: #force_inline proc(c: Counter, n: u64 = 1) {
	b := tl_block
	if b == nil { b = counters_block() }
	b.v[c] += n
}

set :: proc "contextless" (g: Gauge, v: i64) {
	sync.atomic_store_explicit(&reg.gauge[g], v, .Relaxed)
}

add :: proc "contextless" (g: Gauge, v: i64) {
	sync.atomic_add_explicit(&reg.gauge[g], v, .Relaxed)
}

// Any thread's first count allocates its block (an event loop's in thread_init).
@(private)
counters_block :: proc() -> ^Block {
	if tl_block != nil { return tl_block }
	b := new(Block)
	sync.mutex_lock(&reg.blocks_mu)
	defer sync.mutex_unlock(&reg.blocks_mu)
	n := sync.atomic_load(&reg.nblocks)
	if n == MAX_THREADS { // a thread beyond the table counts into the last block, unsafely but boundedly
		free(b)
		tl_block = reg.blocks[n - 1]
		return tl_block
	}
	reg.blocks[n] = b
	sync.atomic_store(&reg.nblocks, n + 1)
	tl_block = b
	return b
}

counter_value :: proc(c: Counter) -> (sum: u64) {
	n := sync.atomic_load(&reg.nblocks)
	for b in reg.blocks[:n] {
		sum += sync.atomic_load_explicit(&b.v[c], .Relaxed)
	}
	return
}

gauge_value :: proc(g: Gauge) -> i64 {
	return sync.atomic_load_explicit(&reg.gauge[g], .Relaxed)
}

// ---- loop ticks: what /livez and the watchdog read --------------------------

tick :: proc "contextless" (loop: int) {
	sync.atomic_store_explicit(&loop_ticks[loop], sys.mono_ns(), .Relaxed)
}

// The loop that ticked longest ago, and how long ago. -1 before any loop runs.
oldest_tick :: proc() -> (loop: int, age_ns: i64) {
	loop = -1
	now := sys.mono_ns()
	for i in 0 ..< sync.atomic_load(&loops) {
		t := sync.atomic_load_explicit(&loop_ticks[i], .Relaxed)
		if t != 0 && now - t >= age_ns {
			loop, age_ns = i, now - t
		}
	}
	return
}

// ---- the scrape -------------------------------------------------------------

// Prometheus text 0.0.4. A family's lines are contiguous, as the format requires,
// whatever order its members were registered in.
render :: proc(b: ^strings.Builder) {
	done := make([]bool, len(reg.metrics), context.temp_allocator)
	for m, i in reg.metrics {
		if done[i] { continue }
		fmt.sbprintf(b, "# HELP %s %s\n# TYPE %s %s\n", m.name, m.help, m.name, "counter" if m.kind == .Counter else "gauge")
		for n, j in reg.metrics[i:] {
			if n.name != m.name { continue }
			done[i + j] = true
			strings.write_string(b, n.name)
			if n.labels != "" {
				strings.write_byte(b, '{')
				strings.write_string(b, n.labels)
				strings.write_byte(b, '}')
			}
			strings.write_byte(b, ' ')
			if n.kind == .Counter {
				strings.write_u64(b, counter_value(Counter(n.index)))
			} else {
				strings.write_i64(b, gauge_value(Gauge(n.index)))
			}
			strings.write_byte(b, '\n')
		}
	}
	strings.write_string(b, "# HELP app_loop_tick_age_seconds Time since each event loop's last 1 s tick.\n# TYPE app_loop_tick_age_seconds gauge\n")
	now := sys.mono_ns()
	for i in 0 ..< sync.atomic_load(&loops) {
		t := sync.atomic_load_explicit(&loop_ticks[i], .Relaxed)
		fmt.sbprintf(b, "app_loop_tick_age_seconds{{loop=\"%d\"}} %.3f\n", i, f64(now - t) / 1e9 if t != 0 else 0)
	}
}
