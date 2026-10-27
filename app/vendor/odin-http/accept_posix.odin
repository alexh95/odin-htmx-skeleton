#+build linux, darwin, freebsd, openbsd, netbsd
#+private
package http

import "core:net"

// F-19: Windows' accepted sockets need the listener's context (accept_windows.odin); here an
// accepted socket is whole.
_accepted :: proc(listener, client: net.TCP_Socket) {}
