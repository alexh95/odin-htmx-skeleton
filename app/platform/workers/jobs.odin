package workers

// ---- the scheduler over the mounted JOBS rows ------------------------------
//
// A profile mounts each feature's `JOBS` table (PLAN §7.2) and app.serve hands
// them here. One thread wakes every second and runs what is due, guarded, one
// job at a time; `run_now` asks for a run at the next wake, as the jobs page's
// button will (M5). Each job's state is plain data for that page to read. Daily
// runs at a local time (the nightly demo resets, M4) are still to come: today a
// job runs every `every`.

import "core:sync"
import "core:thread"
import "core:time"

import "../guard"
import "../obs"
import "../sys"

Job :: struct {
	id:    string, // "notify.prune": the feature's prefix, then the job
	every: time.Duration,
	run:   proc(), // on the scheduler's thread, guarded
}

Job_State :: struct {
	runs, crashes:    int,
	last_start_ns:    i64, // unix ns, 0 = never
	last_ms:          i64,
	next_ns:          i64, // mono ns
	running, wanted:  bool,
}

@(private)
sched: struct {
	mu:     sync.Mutex,
	jobs:   []Job,
	state:  []Job_State,
	stop:   bool, // atomic
	thread: ^thread.Thread,
}

// Once, after the loops run. The tables are the profile's package-level JOBS.
schedule :: proc(tables: [][]Job) {
	n := 0
	for t in tables { n += len(t) }
	if n == 0 { return }
	sched.jobs = make([]Job, n)
	sched.state = make([]Job_State, n)
	i := 0
	now := sys.mono_ns()
	for t in tables {
		for j in t {
			sched.jobs[i] = j
			sched.state[i].next_ns = now + i64(j.every)
			i += 1
		}
	}
	sched.thread = thread.create_and_start(scheduler, context)
}

// Asks for a run at the next wake. false: no such job.
run_now :: proc(id: string) -> bool {
	sync.mutex_lock(&sched.mu)
	defer sync.mutex_unlock(&sched.mu)
	for j, i in sched.jobs {
		if j.id == id {
			sched.state[i].wanted = true
			return true
		}
	}
	return false
}

// A copy for a page to read.
job_state :: proc(id: string) -> (s: Job_State, ok: bool) {
	sync.mutex_lock(&sched.mu)
	defer sync.mutex_unlock(&sched.mu)
	for j, i in sched.jobs {
		if j.id == id { return sched.state[i], true }
	}
	return
}

// At drain: no new runs; a running job finishes, and exit doesn't wait for it.
unschedule :: proc() {
	sync.atomic_store(&sched.stop, true)
}

@(private)
scheduler :: proc() {
	guard.thread_init()
	for !sync.atomic_load(&sched.stop) {
		time.sleep(time.Second)
		for i in 0 ..< len(sched.jobs) {
			if sync.atomic_load(&sched.stop) { return }
			now := sys.mono_ns()
			sync.mutex_lock(&sched.mu)
			st := &sched.state[i]
			due := st.wanted || now >= st.next_ns
			if due {
				st.running, st.wanted = true, false
				st.last_start_ns = sys.now_unix_ns()
			}
			sync.mutex_unlock(&sched.mu)
			if !due { continue }

			job := sched.jobs[i]
			ok := guard.call(proc(data: rawptr) { (proc())(data)() }, rawptr(job.run))
			if l, lok := obs.begin(.Info if ok else .Error, "jobs", "run"); lok {
				obs.str(&l, "job", job.id)
				obs.num(&l, "ms", (sys.mono_ns() - now) / 1e6)
				if !ok { obs.str(&l, "result", "crashed") }
				obs.end(&l)
			}
			sync.mutex_lock(&sched.mu)
			st.running = false
			st.runs += 1
			if !ok { st.crashes += 1 }
			st.last_ms = (sys.mono_ns() - now) / 1e6
			st.next_ns = sys.mono_ns() + i64(job.every)
			sync.mutex_unlock(&sched.mu)
			free_all(context.temp_allocator)
		}
	}
}
