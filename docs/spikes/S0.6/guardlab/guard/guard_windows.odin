#+build windows
package guard

import "core:c/libc"
import win32 "core:sys/windows"

foreign import ucrt "system:libucrt.lib"
@(default_calling_convention = "c")
foreign ucrt {
	_resetstkoflw :: proc() -> i32 ---
}

Jmp_Buf :: libc.jmp_buf
_setjmp :: libc.setjmp // called directly in invoke's frame (an alias, not a wrapper)

@(private)
_jump :: proc "contextless" (env: ^Jmp_Buf) -> ! {
	libc.longjmp(env, 1)
}

@(private)
_veh :: proc "system" (info: ^win32.EXCEPTION_POINTERS) -> win32.LONG {
	code := u32(info.ExceptionRecord.ExceptionCode)
	kind: string
	switch code {
	case 0xC000008C: kind = "bounds"        // EXCEPTION_ARRAY_BOUNDS_EXCEEDED: Odin's bounds trap
	case 0xC000001D: kind = "trap"          // EXCEPTION_ILLEGAL_INSTRUCTION: intrinsics.trap
	case 0xC0000094: kind = "int_div_zero"
	case 0xC0000095: kind = "int_overflow"  // min(int) / -1
	case 0xC0000005: kind = "access_violation"
	case 0xC00000FD: kind = "stack_overflow"
	case:
		return win32.EXCEPTION_CONTINUE_SEARCH
	}
	_jump_from_trap(kind, code)
	return win32.EXCEPTION_CONTINUE_SEARCH
}

@(private)
_install_trap_handlers :: proc() {
	win32.AddVectoredExceptionHandler(1, _veh)
}

@(private)
_thread_init :: proc() {}

// Without this the guard page stays gone, and the next overflow kills the process (13 §1.2).
@(private)
_after_trap :: proc(code: u32) {
	if code == 0xC00000FD { _resetstkoflw() }
}
