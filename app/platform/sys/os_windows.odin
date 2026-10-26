#+build windows
package sys

import "core:time"

// Windows has no per-process soft limit on sockets to raise.
raise_nofile :: proc() -> (soft: int) {
	return -1
}

// Both are fast here already: GetSystemTimePreciseAsFileTime and QueryPerformanceCounter.
now_unix_ns :: proc "contextless" () -> i64 {
	return time.now()._nsec
}

mono_ns :: proc "contextless" () -> i64 {
	return time.tick_now()._nsec
}
