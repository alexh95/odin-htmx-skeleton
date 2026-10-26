package s05

import "core:os"
import "core:sys/linux"

// ARGON_SCHED=idle runs the calling worker under SCHED_IDLE, so it only gets CPU time the loops
// leave; nice puts it at nice 19. Unset leaves the default policy. PIN=1 keeps the workers on
// CPUs 2-3 and the loops on 0-1 (loop_pin), to tell CPU sharing inside the box from the rest.
worker_priority :: proc() {
	switch os.get_env("ARGON_SCHED", context.temp_allocator) {
	case "idle":
		param: linux.Sched_Param
		_ = linux.sched_setscheduler(0, i32(linux.Sched_Policy.IDLE), &param)
	case "nice":
		_ = linux.setpriority(.PROCESS, i32(linux.gettid()), 19)
	}
	if os.get_env("PIN", context.temp_allocator) == "1" { pin({2, 3}) }
}

loop_pin :: proc() {
	if os.get_env("PIN", context.temp_allocator) == "1" { pin({0, 1}) }
}

pin :: proc(cpus: linux.Cpu_Set) {
	cpus := cpus
	_, _ = linux.sched_setaffinity(0, size_of(cpus), &cpus)
}
