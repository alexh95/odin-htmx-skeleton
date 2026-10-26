package sys

// ---- platform/sys: the OS pieces under the guard and the clocks (L1) ------
//
// Bindings and thread-local primitives only, no policy: glibc's `_setjmp`, the
// trap handlers (sigaction with a per-thread alternate stack on POSIX, a vectored
// exception handler and `_resetstkoflw` on Windows), the open-file limit, and a
// fast wall clock (PLAN §5.2, §10.2). `platform/guard` decides what a trap means;
// `platform/sqlite` keeps `in_sqlite` here, because L1 can't import the guard.

// What the guard classifies a trap by (D15 rule 2). Each thread owns its block;
// only the helpers in platform/guard and platform/sqlite touch it.
Counters :: struct {
	locks_held:   int, // guard.Mutex held by this thread
	async_posted: int, // ops this callback posted that run later against its state
	in_sqlite:    int, // inside a call into SQLite's C code
}

@(thread_local)
counters: Counters

// The trap handler's callback: jump back into the guarded frame, or return false
// when this thread isn't inside one, and the process dies as it would have.
// `kind` names the trap for the crash line; `code` is the signal or exception code.
On_Trap :: #type proc "contextless" (kind: string, code: u32) -> bool

@(private)
on_trap: On_Trap

// Installs the process-wide trap handlers. Once, at boot, before any thread starts.
install_trap_handlers :: proc(handler: On_Trap) {
	on_trap = handler
	_install_trap_handlers()
}

// Per-thread setup the handlers need (the alternate signal stack on POSIX, without
// which a stack overflow can't run its handler). Every thread that runs guarded
// code calls it once: the loops from F-4's on_thread_init, the workers at start.
thread_init :: proc() {
	_thread_init()
}

// After a recovered trap, before the thread runs guarded code again.
after_trap :: proc(code: u32) {
	_after_trap(code)
}
