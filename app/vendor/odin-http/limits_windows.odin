#+private
package http

// F-8: Windows has no open-file limit for sockets, so there is no default cap.
_default_max_connections :: proc() -> int {
	return -1
}
