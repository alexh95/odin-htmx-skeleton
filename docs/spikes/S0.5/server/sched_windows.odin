package s05

import "core:os"
import win "core:sys/windows"

// ARGON_SCHED=idle runs the calling worker at THREAD_PRIORITY_IDLE, nice at THREAD_PRIORITY_LOWEST.
worker_priority :: proc() {
	switch os.get_env("ARGON_SCHED", context.temp_allocator) {
	case "idle": win.SetThreadPriority(win.GetCurrentThread(), win.THREAD_PRIORITY_IDLE)
	case "nice": win.SetThreadPriority(win.GetCurrentThread(), win.THREAD_PRIORITY_LOWEST)
	}
}

loop_pin :: proc() {}
