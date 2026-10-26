package web

// ---- the server: the fork's listen, loops and shutdown, for platform/app --------
//
// platform/app composes boot, serve and drain (§8.6, §8.7) without touching
// odin-http's types: it hands this file its front proc, its per-loop hooks and
// the options, and gets the loops running on a server thread. The fork's own
// signal handler isn't used: app.wait returns on the signal, so a profile's drain
// calls run before the shutdown starts.

import "core:net"
import "core:sync"
import "core:thread"
import "core:time"

import http "../../vendor/odin-http"
import "../guard"

Server_Config :: struct {
	endpoint:        net.Endpoint,
	threads:         int,
	header_timeout:  time.Duration,
	idle_timeout:    time.Duration,
	body_timeout:    time.Duration,
	drain_deadline:  time.Duration,
	max_connections: int, // 0 = the fd soft limit − 64 (F-8)
	front:           Handler, // every request, whatever its route
	on_loop_start:   proc(loop: int), // F-4, on each loop as it starts
	on_loop_stop:    proc(loop: int), // F-4, on each loop as its shutdown starts
}

@(private)
srv: struct {
	server:  http.Server,
	cfg:     Server_Config,
	thread:  ^thread.Thread,
	started: sync.Wait_Group, // every loop ran its on_loop_start
	listen:  net.Network_Error,
	bound:   sync.Sema,
}

// Binds (retrying 3 s on Address_In_Use, F-12) and starts the loops on a server
// thread; returns once every loop runs, or the bind's error.
start :: proc(cfg: Server_Config) -> net.Network_Error {
	srv.cfg = cfg
	sync.wait_group_add(&srv.started, max(1, cfg.threads))
	srv.thread = thread.create_and_start(server_run, context)
	sync.sema_wait(&srv.bound)
	if srv.listen != nil { return srv.listen }
	sync.wait(&srv.started)
	return nil
}

@(private)
server_run :: proc() {
	cfg := srv.cfg
	opts := http.Default_Server_Opts
	opts.thread_count = cfg.threads
	opts.auto_expect_continue = false // see front: the skeleton turned odin-http's own 100-continue off
	opts.invoke = guard.invoke
	opts.header_timeout = cfg.header_timeout
	opts.idle_timeout = cfg.idle_timeout
	opts.body_timeout = cfg.body_timeout
	opts.drain_deadline = cfg.drain_deadline
	opts.max_connections = cfg.max_connections
	opts.on_thread_init = proc(_: ^http.Server, i: int) {
		srv.cfg.on_loop_start(i)
		sync.wait_group_done(&srv.started)
	}
	opts.on_thread_shutdown = proc(_: ^http.Server, i: int) {
		srv.cfg.on_loop_stop(i)
	}
	srv.listen = http.listen(&srv.server, cfg.endpoint, opts)
	sync.sema_post(&srv.bound)
	if srv.listen != nil { return }
	h := http.Handler{handle = proc(_: ^http.Handler, req: ^Request, res: ^Response) { srv.cfg.front(req, res) }}
	http.serve(&srv.server, h)
}

// Starts the fork's bounded shutdown (F-9) and waits for every loop to finish.
stop :: proc() {
	if srv.thread == nil { return }
	http.server_shutdown(&srv.server)
	thread.join(srv.thread)
	thread.destroy(srv.thread)
	srv.thread = nil
}

is_closing :: proc() -> bool {
	return http.server_is_closing(&srv.server)
}
