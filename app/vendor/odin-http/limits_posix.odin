#+build linux, darwin, freebsd, openbsd, netbsd
#+private
package http

import "core:sys/posix"

// F-8: the default connection cap, the open-file soft limit less 64 for listeners, logs and files.
// Past the soft limit accept fails, and upstream then stopped accepting for good.
_default_max_connections :: proc() -> int {
	lim: posix.rlimit
	if posix.getrlimit(.NOFILE, &lim) != .OK || lim.rlim_cur == posix.RLIM_INFINITY {
		return -1
	}
	return max(int(lim.rlim_cur) - 64, 64)
}
