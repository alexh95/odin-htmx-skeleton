// S0.5 argon2id timings: n verifies per preset, alone and two at once (the pool's default
// width), with the scratch memory freshly allocated each time (what `derive` does with the
// heap) and reused from a per-thread buffer.
//
//   odin run . -o:speed -- [n]
package bench

import "core:crypto"
import "core:crypto/argon2id"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:sync"
import "core:thread"
import "core:time"

Preset :: struct {
	name: string,
	p:    argon2id.Parameters,
}

PRESETS := [?]Preset{
	{"OWASP 19 MiB t2 p1", argon2id.PARAMS_OWASP},
	{"OWASP_SMALL 7 MiB t5 p1", argon2id.PARAMS_OWASP_SMALL},
	{"64 MiB t3 p1", {memory_size = 64 * 1024, passes = 3, parallelism = 1}},
}

PASSWORD :: "correct horse battery staple"

Mode :: enum {
	Fresh,  // derive's own allocation from the heap, every call
	Reused, // one buffer per thread, reset before each call
}

// One verify: derive into a tag (the compare is free next to it).
verify :: proc(p: ^argon2id.Parameters, salt: []byte, mode: Mode, buf: []byte) -> time.Duration {
	tag: [32]byte
	start := time.tick_now()
	switch mode {
	case .Fresh:
		_ = argon2id.derive(p, transmute([]byte)string(PASSWORD), salt, tag[:])
	case .Reused:
		arena: mem.Arena
		mem.arena_init(&arena, buf)
		_ = argon2id.derive(p, transmute([]byte)string(PASSWORD), salt, tag[:], allocator = mem.arena_allocator(&arena))
	}
	return time.tick_since(start)
}

Worker :: struct {
	p:       ^argon2id.Parameters,
	salt:    []byte,
	mode:    Mode,
	n:       int,
	out:     []time.Duration,
	barrier: ^sync.Barrier,
}

run_worker :: proc(w: ^Worker) {
	buf: []byte
	if w.mode == .Reused { buf = make([]byte, int(w.p.memory_size) * 1024 + 64 * 1024) }
	defer delete(buf)
	_ = verify(w.p, w.salt, w.mode, buf) // warm-up, not counted
	for i in 0 ..< w.n {
		sync.barrier_wait(w.barrier) // both threads start each verify together
		w.out[i] = verify(w.p, w.salt, w.mode, buf)
	}
}

ms :: proc(d: time.Duration) -> f64 { return time.duration_milliseconds(d) }

report :: proc(name: string, mode: Mode, width: int, ds: []time.Duration) {
	slice.sort(ds)
	sum: time.Duration
	for d in ds { sum += d }
	n := len(ds)
	median := (ds[(n - 1) / 2] + ds[n / 2]) / 2
	fmt.printfln("| %s | %v | %d | %d | %.1f | %.1f | %.1f | %.1f |",
		name, mode, width, n, ms(ds[0]), ms(median), ms(sum / time.Duration(n)), ms(ds[n - 1]))
}

main :: proc() {
	n := 10
	if len(os.args) > 1 { n, _ = strconv.parse_int(os.args[1]) }

	salt: [16]byte
	crypto.rand_bytes(salt[:])

	fmt.printfln("| preset | memory | threads | n | min ms | median ms | mean ms | max ms |")
	fmt.printfln("|---|---|---:|---:|---:|---:|---:|---:|")
	for &pr in PRESETS {
		for mode in Mode {
			for width in 1 ..= 2 {
				barrier: sync.Barrier
				sync.barrier_init(&barrier, width)
				ws := make([]Worker, width)
				all := make([]time.Duration, n * width)
				threads := make([]^thread.Thread, width)
				for &w, i in ws {
					w = {p = &pr.p, salt = salt[:], mode = mode, n = n, out = all[i * n:][:n], barrier = &barrier}
					threads[i] = thread.create_and_start_with_poly_data(&w, run_worker)
				}
				for t in threads { thread.join(t); thread.destroy(t) }
				// Two at once: n per thread, both counted (2n samples).
				report(pr.name, mode, width, all)
				delete(ws); delete(all); delete(threads)
			}
		}
	}
}
