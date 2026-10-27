package main

// ---- tools/profile's spall hook (never in a profile of the repo) ----------------------------
//
// profile.sh --spall copies this file into a scratch copy of app/cmd/<profile>/ and
// builds that copy: defining the two instrumentation procs makes the compiler call
// them around every procedure it compiles, and each call becomes a spall event in
// the thread's own buffer, written to SPALL_FILE. Instrumentation inflates every
// call (each bounds check is one), so the trace's times are not the profile; its
// exact call counts are (docs/audit/M1.md, Profile). A buffer still unflushed at
// exit is lost: the trace's tail, which the run's length makes up for.

import "base:runtime"
import "core:os"
import "core:prof/spall"
import "core:sync"

@(private = "file") spall_ctx: spall.Context
@(private = "file", thread_local) spall_buf: spall.Buffer
@(private = "file", thread_local) spall_ready: bool
@(private = "file", thread_local) spall_busy: bool // what the hook itself calls isn't traced

@(init, no_instrumentation)
spall_open :: proc "contextless" () {
	context = runtime.default_context()
	path, ok := os.lookup_env("SPALL_FILE", context.allocator)
	spall_ctx = spall.context_create(path if ok && path != "" else "trace.spall")
}

@(no_instrumentation)
spall_thread :: proc "contextless" () {
	context = runtime.default_context()
	spall_buf = spall.buffer_create(make([]u8, spall.BUFFER_DEFAULT_SIZE), u32(sync.current_thread_id()))
	spall_ready = true
}

@(instrumentation_enter)
spall_enter :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
	if spall_busy { return }
	spall_busy = true
	if !spall_ready { spall_thread() }
	spall._buffer_begin(&spall_ctx, &spall_buf, "", "", loc)
	spall_busy = false
}

@(instrumentation_exit)
spall_exit :: proc "contextless" (proc_address, call_site_return_address: rawptr, loc: runtime.Source_Code_Location) {
	if spall_busy || !spall_ready { return }
	spall_busy = true
	spall._buffer_end(&spall_ctx, &spall_buf)
	spall_busy = false
}
