package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"

import http "../odin-http"
import "repository"

// ---- entry --------------------------------------------------------------
//
// Seed the store, wire the routes, serve. Port resolves PORT env -> first arg
// -> default (the platform injects PORT in a container). BIND_ALL switches the
// listen address from loopback (the safe local default) to 0.0.0.0 so a
// container host can route traffic in; locally we stay on loopback.

DEFAULT_PORT :: 8080

main :: proc() {
	env: [64]u8

	port := DEFAULT_PORT
	if v, _ := os.lookup_env(env[:], "PORT"); v != "" {
		if p, ok := strconv.parse_int(v); ok {
			port = p
		}
	} else if len(os.args) > 1 {
		if p, ok := strconv.parse_int(os.args[1]); ok {
			port = p
		}
	}

	address := net.IP4_Loopback
	host := "localhost"
	if v, _ := os.lookup_env(env[:], "BIND_ALL"); v != "" {
		address = net.IP4_Any
		host = "0.0.0.0"
	}

	repository.repo_seed()

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
		address = address,
		port    = port,
	}

	fmt.printfln("odin-htmx-demo listening on http://%s:%d", host, port)
	if err := http.listen_and_serve(&s, http.router_handler(&router), endpoint, opts); err != nil {
		fmt.eprintfln("server error: %v", err)
		os.exit(1)
	}
}
