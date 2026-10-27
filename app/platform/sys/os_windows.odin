#+build windows
package sys

import win32 "core:sys/windows"
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

// Whether a process with this id still runs. One that exists but isn't ours to
// ask counts as running: its files aren't ours to delete either.
process_alive :: proc(pid: int) -> bool {
	h := win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, false, win32.DWORD(pid))
	if h == nil { return win32.GetLastError() == win32.ERROR_ACCESS_DENIED }
	defer win32.CloseHandle(h)
	STILL_ACTIVE :: 259
	code: win32.DWORD
	return bool(win32.GetExitCodeProcess(h, &code)) && code == STILL_ACTIVE
}

// The process's working set, in bytes (ops's panel).
rss_bytes :: proc() -> int {
	pmc: win32.PROCESS_MEMORY_COUNTERS
	if !win32.GetProcessMemoryInfo(win32.GetCurrentProcess(), &pmc, size_of(pmc)) { return 0 }
	return int(pmc.WorkingSetSize)
}
