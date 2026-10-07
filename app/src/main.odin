package main

import "core:fmt"
import "core:log"
import "core:net"
import "core:os"
import "core:strconv"

import http "../odin-http"
import "controllers"
import "repository"
import "views"

// ---- entry --------------------------------------------------------------
//
// Set up logging, open (and maybe seed) the store, wire the routes, serve; or,
// with --backup, copy the store and exit. Port resolves PORT env -> first arg
// -> default (the platform injects PORT in a container). BIND_ALL switches the
// listen address from loopback (the safe local default) to 0.0.0.0 so a
// container host can route traffic in; locally we stay on loopback.

DEFAULT_PORT :: 8080

main :: proc() {
	env: [64]u8

	// Odin's default logger discards everything, odin-http's own warnings
	// included, so install a real one before anything can log. The server's
	// threads are started with this context, so they inherit it. LOG_LEVEL
	// (debug|info|warn|error) sets the floor; at warn the access log is off.
	level := log.Level.Info
	switch v, _ := os.lookup_env(env[:], "LOG_LEVEL"); v {
	case "debug":
		level = .Debug
	case "warn", "warning":
		level = .Warning
	case "error":
		level = .Error
	}
	context.logger = log.create_console_logger(level, {.Level, .Date, .Time, .Terminal_Color})

	// `<bin> --backup <path>`: write a consistent copy of DB_PATH to <path> and
	// exit, beside a running server or not (repository.repo_backup).
	if len(os.args) > 1 && os.args[1] == "--backup" {
		os.exit(backup(os.args[2:]))
	}

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

	// The banner prints 127.0.0.1, not localhost: the server listens on IPv4
	// loopback only, and "localhost" tries ::1 first, which on Windows costs about
	// 200 ms per request before falling back.
	address := net.IP4_Loopback
	host := "127.0.0.1"
	if v, _ := os.lookup_env(env[:], "BIND_ALL"); v != "" {
		address = net.IP4_Any
		host = "0.0.0.0"
	}

	// DB_PATH selects the SQLite backend: unset/":memory:" is the test/dev
	// default (a real in-RAM SQLite, seeded fresh per boot, gone on exit — the
	// isolation the e2e/load suites rely on); a real file path persists (prod sets
	// it to a mounted volume). repo_open must run before repo_seed.
	//
	// Demo rows go only into a store nobody owns yet: :memory:, or a file when
	// SEED=1 asks (run.* sets it for local dev). A production table emptied on
	// purpose must not come back full of samples on the next deploy.
	db_path := os.get_env("DB_PATH", context.allocator)
	if db_path == "" {
		db_path = ":memory:"
	}
	// SITE_URL names the canonical origin used by the canonical/og:url tags, the
	// sitemap, and the *.fly.dev redirect. A fork sets it in the environment
	// instead of editing brand.odin. A placeholder origin leaves the redirect off
	// (see controllers.canonical_host).
	if v := os.get_env("SITE_URL", context.allocator); v != "" {
		views.SITE_URL = v
	}
	controllers.canonical_redirect = !controllers.placeholder_origin(views.SITE_URL)

	repository.repo_open(db_path)
	defer repository.repo_close() // runs after the server loop returns (clean shutdown)
	if seed, _ := os.lookup_env(env[:], "SEED"); db_path == ":memory:" || seed == "1" {
		repository.repo_seed()
	}
	controllers.init_etags()
	controllers.init_security()

	router: http.Router
	http.router_init(&router)
	defer http.router_destroy(&router)
	build_router(&router)

	s: http.Server
	http.server_shutdown_on_interrupt(&s)

	// N event-loop threads, one per core by default; the store is guarded by an
	// RW_Mutex (see repository/db.odin) so handlers can run concurrently. THREADS
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

	fmt.printfln("odin-htmx-skeleton listening on http://%s:%d (%d threads)", host, port, opts.thread_count)
	log.infof("version %s, store %s, site %s", controllers.VERSION, db_path, views.SITE_URL)
	routes := http.router_handler(&router)
	if err := http.listen_and_serve(&s, http.middleware_proc(&routes, controllers.front), endpoint, opts); err != nil {
		fmt.eprintfln("server error: %v", err)
		os.exit(1)
	}
}

backup :: proc(args: []string) -> int {
	db_path := os.get_env("DB_PATH", context.temp_allocator)
	if len(args) != 1 || db_path == "" || db_path == ":memory:" {
		fmt.eprintln("usage: DB_PATH=<live db> <bin> --backup <new file>   (DB_PATH must be a file)")
		return 2
	}
	if problem := repository.repo_backup(db_path, args[0]); problem != "" {
		fmt.eprintfln("backup: %s", problem)
		return 1
	}
	fmt.printfln("backup: %s -> %s", db_path, args[0])
	return 0
}
