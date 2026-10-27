package status

// ---- status: the domain (PLAN §15.4, D36) -------------------------------------------------
//
// What the status page shows, one probe a line: every module's health as it pushed it to obs
// (§10.4), whether every event loop still ticks, and the process itself. M5 adds the
// STATUS_PROBES externals (llama, the Pi agent, disk, backups), each with its 2 s timeout.
// Plain values, never HTTP.

import "core:fmt"
import "core:hash"
import "core:time"

import "../../platform/obs"
import "../../platform/sys"

// A loop that hasn't ticked for this long is stuck (/livez says the same at 30 s, and the
// watchdog exits at 10 s: past 2 s the page already says something is wrong).
STUCK :: 2 * time.Second

Probe :: struct {
	name, state, message: string,
}

@(private)
started_ns: i64

init :: proc() {
	started_ns = sys.mono_ns()
}

board :: proc(version: string, out: ^[dynamic]Probe) {
	for h in obs.modules() { append(out, Probe{h.module, obs.STATE_NAMES[h.state], h.message}) }
	loop, age := obs.oldest_tick()
	if age > i64(STUCK) {
		append(out, Probe{"loops", "down", fmt.tprintf("loop %d last ticked %d ms ago", loop, age / 1e6)})
	} else {
		append(out, Probe{"loops", "ok", fmt.tprintf("%d ticking", obs.loops)})
	}
	up := time.Duration(sys.mono_ns() - started_ns)
	append(out, Probe{"process", "ok", fmt.tprintf("up %s, version %s", uptime(up), version)})
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
