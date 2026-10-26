#+build linux, darwin, freebsd, openbsd, netbsd
package guardlab

import "core:sys/posix"

raise_nofile :: proc() {
	lim: posix.rlimit
	if posix.getrlimit(.NOFILE, &lim) != .OK { return }
	lim.rlim_cur = lim.rlim_max
	posix.setrlimit(.NOFILE, &lim)
}
