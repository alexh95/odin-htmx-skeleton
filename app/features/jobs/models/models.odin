package jobs_models

// ---- jobs: the types and the store contract ------------------------------------------------
//
// PLAN §15.4, 13 §3.6. platform/workers keeps each run as data for the process's life; this
// feature keeps them past it, in `jobs_runs`, one row per run, keyed by the boot that ran it and
// the run's id in that boot. A queued or running row holds a lease the sync renews; a row whose
// lease lapsed under another boot was interrupted by a restart and is marked failed. Times are
// unix ms.

import "../../../platform/store"

Error :: store.Error

Run_Row :: struct {
	boot:        i64, // the process's boot, unix ms
	id:          i64, // the run's id in that boot
	job:         string,
	state:       string, // workers.RUN_STATE_NAMES, or "failed" for an interrupted one
	by_hand:     bool,
	queued_at:   i64,
	started_at:  i64,
	ended_at:    i64,
	done, total: i64,
	log:         string,
	note:        string, // why it ended as it did, when the run didn't say: "interrupted by a restart"
	lease_until: i64, // a queued or running row: the sync renews it while this boot lives
}

// Upserted by (boot, id), in one transaction, now: the sync runs on the scheduler's thread,
// which has no loop for a queued write to answer on.
Store_Save :: proc(rows: []Run_Row) -> Error
// The newest `limit` runs, newest first, with no log (the page's table).
Store_Recent :: proc(limit: int, into: ^[dynamic]Run_Row) -> Error
// One run, its log too.
Store_Run :: proc(boot, id: i64) -> (Run_Row, Error)
// Every queued or running row of another boot whose lease lapsed before `now`: failed, as
// interrupted by a restart, now. How many.
Store_Fail_Lapsed :: proc(boot, now: i64) -> (int, Error)
// Rows that ended before `before` go: the table keeps 30 days.
Store_Prune :: proc(before: i64) -> (int, Error)
