package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"

import http "../odin-http"
import "controllers"
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

	// DB_PATH selects the SQLite backend: unset/":memory:" is the test/dev
	// default (a real in-RAM SQLite, seeded fresh per boot, gone on exit — the
	// isolation the e2e/load suites rely on); a real file path persists (prod sets
	// it to a mounted volume). repo_open must run before repo_seed.
	db_path := os.get_env("DB_PATH", context.allocator)
	if db_path == "" {
		db_path = ":memory:"
	}
	repository.repo_open(db_path)
	defer repository.repo_close() // runs after the server loop returns (clean shutdown)
	repository.repo_seed()
	controllers.init_etags()

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)
	build_router(&router)

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	// N event-loop threads, one per core by default; the store is guarded by an
	// RW_Mutex (see repository.odin) so handlers can run concurrently. THREADS
	// overrides the count — load-tests sweep it (THREADS=1 reproduces the old
	// single-thread baseline against the same binary).
	opts := http.Default_Server_Opts
	opts.thread_count = os.get_processor_core_count()
	if v, _ := os.lookup_env(env[:], "THREADS"); v != "" {
		if n, ok := strconv.parse_int(v); ok && n > 0 {
			opts.thread_count = n
		}
	}

	endpoint := net.Endpoint {
		address = address,
		port    = port,
	}

	fmt.printfln("odin-htmx-demo listening on http://%s:%d (%d threads)", host, port, opts.thread_count)
	if err := http.listen_and_serve(&s, http.router_handler(&router), endpoint, opts); err != nil {
		fmt.eprintfln("server error: %v", err)
		os.exit(1)
	}
}
