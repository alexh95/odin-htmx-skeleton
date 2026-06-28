package repository

import "../models"
import "../sqlite"

import "core:c"
import "core:sync"
import "core:time"

// ---- events table -------------------------------------------------------
//
// The second entity, related to contacts by two FKs (actor/target, both ON
// DELETE CASCADE). The one user-facing read is the per-contact timeline, which
// JOINs back to contacts to resolve the other party — the multi-table query.
// Events are seeded only (no user-facing write path yet).

@(private = "file") q_event_create, q_timeline, q_event_count: sqlite.Stmt

@(private = "file") SQL_EVENT_CREATE: cstring : "INSERT INTO events(actor_id,target_id,kind,at,note) VALUES(?,?,?,?,?)"
@(private = "file") SQL_EVENT_COUNT: cstring : "SELECT count(*) FROM events"

// Every event touching ?1 (as actor or target), newest first, joined to the
// OTHER contact (o). The trailing column is 1 when ?1 was the actor (outgoing).
@(private = "file") SQL_TIMELINE: cstring : `
	SELECT e.id, e.kind, e.at, e.note, o.id, o.name, (e.actor_id = ?1)
	FROM events e
	JOIN contacts o ON o.id = (CASE WHEN e.actor_id = ?1 THEN e.target_id ELSE e.actor_id END)
	WHERE e.actor_id = ?1 OR e.target_id = ?1
	ORDER BY e.at DESC, e.id DESC`

@(private)
prepare_events :: proc() {
	prep(SQL_EVENT_CREATE, &q_event_create)
	prep(SQL_TIMELINE, &q_timeline)
	prep(SQL_EVENT_COUNT, &q_event_count)
}

@(private)
finalize_events :: proc() {
	sqlite.finalize(q_event_create)
	sqlite.finalize(q_timeline)
	sqlite.finalize(q_event_count)
}

// The detail drawer's activity feed: real interactions, other party resolved.
event_timeline :: proc(contact_id: int) -> []models.Interaction {
	sync.rw_mutex_lock(&lock);defer sync.rw_mutex_unlock(&lock)
	defer sqlite.reset(q_timeline)
	sqlite.bind_int(q_timeline, 1, c.int(contact_id))
	out := make([dynamic]models.Interaction, context.temp_allocator)
	for sqlite.step(q_timeline) == sqlite.ROW {
		append(
			&out,
			models.Interaction {
				id = int(sqlite.column_int(q_timeline, 0)),
				kind = models.Event_Kind(sqlite.column_int(q_timeline, 1)),
				at = sqlite.column_int64(q_timeline, 2),
				note = clone_col(q_timeline, 3),
				other_id = int(sqlite.column_int(q_timeline, 4)),
				other_name = clone_col(q_timeline, 5),
				outgoing = sqlite.column_int(q_timeline, 6) != 0,
			},
		)
	}
	return out[:]
}

// ---- internals (caller holds the lock) ----------------------------------

@(private)
count_events :: proc() -> int {
	defer sqlite.reset(q_event_count)
	if sqlite.step(q_event_count) == sqlite.ROW {
		return int(sqlite.column_int(q_event_count, 0))
	}
	return 0
}

@(private = "file")
create_event :: proc(actor_id, target_id: int, kind: models.Event_Kind, at: i64, note: string) {
	defer sqlite.reset(q_event_create)
	sqlite.bind_int(q_event_create, 1, c.int(actor_id))
	sqlite.bind_int(q_event_create, 2, c.int(target_id))
	sqlite.bind_int(q_event_create, 3, c.int(kind))
	sqlite.bind_int64(q_event_create, 4, at)
	bind_text(q_event_create, 5, note)
	sqlite.step(q_event_create)
}

// Deterministic interactions among whatever contacts exist (adapts to the seeded
// set, so it also backfills a contacts-only DB migrated to add this table). Each
// contact acts on three others; timestamps spread over the past ~200 days.
@(private)
seed_events :: proc() {
	ids := make([dynamic]int, context.temp_allocator)
	st: sqlite.Stmt
	prep("SELECT id FROM contacts ORDER BY id", &st)
	for sqlite.step(st) == sqlite.ROW {
		append(&ids, int(sqlite.column_int(st, 0)))
	}
	sqlite.finalize(st)
	n := len(ids)
	if n < 2 {
		return
	}

	now := time.time_to_unix(time.now())
	kinds := [?]models.Event_Kind{.Introduced, .Mentioned, .Reviewed, .Messaged}
	notes := [?]string {
		"after the planning sync",
		"on the platform thread",
		"during code review",
		"re: the incident retro",
		"about the Q3 roadmap",
	}
	DAY :: i64(86400)
	for i in 0 ..< n {
		for k in 0 ..< 3 {
			tgt := ids[(i + 3 + k * 5) % n]
			if tgt == ids[i] {
				continue
			}
			kind := kinds[(i + k) % len(kinds)]
			at := now - i64(2 + (i * 7 + k * 13) % 200) * DAY
			note := notes[(i + k) % len(notes)]
			create_event(ids[i], tgt, kind, at, note)
		}
	}
}
