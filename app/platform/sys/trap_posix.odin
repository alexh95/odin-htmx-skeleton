#+build linux, darwin, freebsd, openbsd, netbsd
package sys

import "core:c/libc"
import "core:sys/posix"

foreign import libc_ "system:c"

// _setjmp saves no signal mask: 3 ns against 298-518 ns for setjmp, which makes a
// syscall (13 §1.5). The handlers run with SA_NODEFER, so there is no blocked mask
// to restore. Call it directly in the guarded frame: a wrapper's frame would be
// gone by the time longjmp returns into it.
@(default_calling_convention = "c")
foreign libc_ {
	@(link_name = "_setjmp") setjmp :: proc(env: ^Jmp_Buf) -> i32 ---
}

Jmp_Buf :: libc.jmp_buf

longjmp :: proc "contextless" (env: ^Jmp_Buf) -> ! {
	libc.longjmp(env, 1)
}

@(private)
_on_signal :: proc "c" (sig: posix.Signal, info: ^posix.siginfo_t, uctx: rawptr) {
	kind := "signal"
	#partial switch sig {
	case .SIGSEGV: kind = "segv"
	case .SIGBUS:  kind = "bus"
	case .SIGFPE:  kind = "fpe"
	case .SIGILL:  kind = "trap" // intrinsics.trap: bounds checks, the default assertion proc
	case .SIGTRAP: kind = "breakpoint"
	}
	if on_trap != nil && on_trap(kind, u32(sig)) { return }
	// Not inside a guard: the default action, so the process dies as it would have.
	sa: posix.sigaction_t
	sa.sa_handler = auto_cast posix.SIG_DFL
	posix.sigaction(sig, &sa, nil)
	posix.raise(sig)
}

@(private)
_install_trap_handlers :: proc() {
	sa: posix.sigaction_t
	sa.sa_sigaction = _on_signal
	sa.sa_flags = {.SIGINFO, .ONSTACK, .SA_NODEFER}
	for s in ([]posix.Signal{.SIGILL, .SIGFPE, .SIGSEGV, .SIGBUS, .SIGTRAP}) {
		posix.sigaction(s, &sa, nil)
	}
}

@(private, thread_local)
_altstack_ready: bool

@(private)
_thread_init :: proc() {
	if _altstack_ready { return }
	_altstack_ready = true
	SIZE :: 64 * 1024
	st: posix.stack_t
	st.ss_sp = raw_data(make([]byte, SIZE))
	st.ss_size = SIZE
	posix.sigaltstack(&st, nil)
}

@(private)
_after_trap :: proc(code: u32) {}
