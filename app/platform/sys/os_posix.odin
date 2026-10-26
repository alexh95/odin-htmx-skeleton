#+build linux, darwin, freebsd, openbsd, netbsd
package sys

import "core:sys/posix"

// Soft to hard (PLAN §8.6 step 2): a container's soft limit is 1024 by default, and at
// that limit the server stopped accepting after 1,012 streams (13 §3.5). F-8's cap
// then derives from the raised limit.
raise_nofile :: proc() -> (soft: int) {
	lim: posix.rlimit
	if posix.getrlimit(.NOFILE, &lim) != .OK { return -1 }
	if lim.rlim_cur < lim.rlim_max {
		lim.rlim_cur = lim.rlim_max
		posix.setrlimit(.NOFILE, &lim)
		posix.getrlimit(.NOFILE, &lim)
	}
	return int(lim.rlim_cur)
}

// libc's clock_gettime goes through the vDSO: 19 ns, against 324-377 ns for the raw
// syscall core:time makes on Linux (13 §5.5). The logger reads these per line.
now_unix_ns :: proc "contextless" () -> i64 {
	ts: posix.timespec
	posix.clock_gettime(.REALTIME, &ts)
	return i64(ts.tv_sec) * 1e9 + i64(ts.tv_nsec)
}

mono_ns :: proc "contextless" () -> i64 {
	ts: posix.timespec
	posix.clock_gettime(.MONOTONIC, &ts)
	return i64(ts.tv_sec) * 1e9 + i64(ts.tv_nsec)
}

// Whether a process with this id still runs: kill(pid, 0) checks without
// signalling. One that exists but isn't ours (EPERM) counts as running.
process_alive :: proc(pid: int) -> bool {
	if posix.kill(posix.pid_t(pid), .NONE) == .OK { return true }
	return posix.errno() == .EPERM
}
