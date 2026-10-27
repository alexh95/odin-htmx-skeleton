#+private
package http

import "core:net"
import win "core:sys/windows"

// F-19: core:nbio sets SO_UPDATE_ACCEPT_CONTEXT on an AcceptEx'd socket with no value, which
// Windows rejects, so the socket never takes the listener's context and shutdown() on it fails
// (Invalid_Argument): F-9's drain cut and the send timeout's cut did nothing. The value is the
// listening socket.
_accepted :: proc(listener, client: net.TCP_Socket) {
	l := win.SOCKET(listener)
	win.setsockopt(win.SOCKET(client), win.SOL_SOCKET, win.SO_UPDATE_ACCEPT_CONTEXT, &l, size_of(l))
}
