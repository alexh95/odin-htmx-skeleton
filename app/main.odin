package demo

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"

import http "odin-http"

// ---- entry --------------------------------------------------------------
//
// Seed the store, wire the routes, serve. The port can be overridden as the
// first argument (run scripts pass it through).

DEFAULT_PORT :: 8080

main :: proc() {
	port := DEFAULT_PORT
	if len(os.args) > 1 {
		if p, ok := strconv.parse_int(os.args[1]); ok {
			port = p
		}
	}

	repo_seed()

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)
	build_router(&router)

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	// One event-loop thread keeps the in-memory store lock-free; see the note
	// in repository.odin.
	opts := http.Default_Server_Opts
	opts.thread_count = 1

	endpoint := net.Endpoint {
		address = net.IP4_Loopback,
		port    = port,
	}

	fmt.printfln("odin-htmx-demo listening on http://localhost:%d", port)
	if err := http.listen_and_serve(&s, http.router_handler(&router), endpoint, opts); err != nil {
		fmt.eprintfln("server error: %v", err)
		os.exit(1)
	}
}
