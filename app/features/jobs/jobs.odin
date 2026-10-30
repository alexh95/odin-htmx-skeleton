package jobs

// ---- jobs: the domain (PLAN §15.4, 13 §3.6, LC §9) ------------------------------------------
//
// platform/workers runs the mounted JOBS rows and keeps each run as data; this feature reads
// them (`workers.runs_since`) into `store:jobs` once a second, so a run outlives the process
// that ran it, and hands the changed ones to the web package for the live page. A queued or
// running row holds a lease of LEASE, renewed every RENEW while this boot lives; a row of
// another boot whose lease lapsed was interrupted by a restart and is marked failed, at boot
// and every minute after (a run isn't resumed: the job runs again when it is next due). Rows
// that ended KEEP ago go. workers never calls a feature: this one reads.

import "core:time"

import "../../platform/sys"
import "../../platform/workers"
import m "models"
import jobs_store "store:jobs"

LEASE :: 30 * time.Second
RENEW :: 10 * time.Second
CHECK_LAPSED :: time.Minute
KEEP :: 30 * 24 * time.Hour

// The runs on the page; their logs only by a run's own link.
RECENT :: 50

@(private)
st: struct {
	boot:        i64, // this process's boot, unix ms: the key's first half
	version:     u64, // the workers' run version last read
	renewed_ns:  i64, // mono
	lapsed_ns:   i64, // mono
	pruned_ns:   i64, // mono
}

boot :: proc() -> i64 { return st.boot }

// At boot, after the migration: the boot's id, and the runs an earlier boot left queued or
// running whose leases lapsed.
init :: proc() {
	st.boot = now_ms()
	st.lapsed_ns = sys.mono_ns()
	_, _ = jobs_store.fail_lapsed(st.boot, st.boot)
}

now_ms :: proc() -> i64 { return sys.now_unix_ns() / 1e6 }

// On the scheduler's thread, once a second: the runs that changed since the last call (and,
// every RENEW, the live ones again, for their leases), saved; they are returned for the page.
sync :: proc() -> (changed: []m.Run_Row, err: m.Error) {
	runs := make([dynamic]workers.Run, context.temp_allocator)
	now_mono := sys.mono_ns()
	renew := now_mono - st.renewed_ns >= i64(RENEW)
	v := workers.runs_since(0 if renew else st.version, &runs)
	if renew { st.renewed_ns = now_mono }
	now := now_ms()
	rows := make([dynamic]m.Run_Row, 0, len(runs), context.temp_allocator)
	for &r in runs {
		live := r.state == .Queued || r.state == .Running
		if renew && r.version <= st.version && !live { continue }
		append(&rows, row_of(&r, now))
	}
	if err = jobs_store.save(rows[:]); err != .None { return nil, err }
	st.version = v
	if now_mono - st.lapsed_ns >= i64(CHECK_LAPSED) {
		st.lapsed_ns = now_mono
		_, _ = jobs_store.fail_lapsed(st.boot, now)
	}
	if now_mono - st.pruned_ns >= i64(time.Hour) {
		st.pruned_ns = now_mono
		_, _ = jobs_store.prune(now - i64(KEEP / time.Millisecond))
	}
	return rows[:], .None
}

@(private)
row_of :: proc(r: ^workers.Run, now: i64) -> m.Run_Row {
	live := r.state == .Queued || r.state == .Running
	log := string(r.log[:r.log_len])
	note := ""
	if r.cut { note = "the log ran out of room: its last lines are missing" }
	if r.cancel && r.state == .Done { note = "asked to stop, it finished first" }
	return m.Run_Row {
		boot = st.boot, id = i64(r.id), job = r.job, state = workers.RUN_STATE_NAMES[r.state], by_hand = r.by_hand,
		queued_at = r.queued_ns / 1e6, started_at = r.started_ns / 1e6, ended_at = r.ended_ns / 1e6,
		done = r.done, total = r.total, log = log, note = note,
		lease_until = now + i64(LEASE / time.Millisecond) if live else 0,
	}
}

recent :: proc(into: ^[dynamic]m.Run_Row) -> m.Error { return jobs_store.recent(RECENT, into) }

run :: proc(boot, id: i64) -> (m.Run_Row, m.Error) { return jobs_store.run(boot, id) }

// Run now: the queued run's id in this boot. ok false: no such job, or too many runs waiting.
run_now :: proc(job: string) -> (id: i64, ok: bool) {
	r, rok := workers.run_now(job)
	return i64(r), rok
}

// Only this boot's runs can be asked to stop: an earlier boot's are over.
cancel :: proc(boot, id: i64) -> bool {
	return boot == st.boot && workers.cancel_run(u64(id))
}

// A job's row for the page: its id, how often, and how its runs have gone.
Job_Row :: struct {
	id:      string,
	every:   time.Duration,
	state:   workers.Job_State,
}

list :: proc(into: ^[dynamic]Job_Row) {
	for j in workers.jobs() {
		s, _ := workers.job_state(j.id)
		append(into, Job_Row{j.id, j.every, s})
	}
}
