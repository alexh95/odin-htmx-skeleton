package dashboard

// ---- dashboard: the domain --------------------------------------------------------------------
//
// The skeleton's root page: live figures from the contacts store (a hard
// dependency, D6), all from one aggregate query, so its cost doesn't grow with
// the table.

import "core:slice"

import "../contacts"

// The dashboard's cards: counts, shares and spreads, all from one aggregate
// query, so its cost doesn't grow with the table. The spreads feed the
// sparklines: distributions, lowest band first, never invented trends.
Stats :: struct {
	total, active, invited, avg_score: int,
	active_pct, invited_pct:           int, // of the total
	by_role:                           []int, // contacts per role, in Role order
	spread, spread_active, spread_invited: []int, // engagement, lowest band first
}

stats :: proc() -> (s: Stats, err: contacts.Error) {
	cs := contacts.stats() or_return
	for n in cs.by_status {
		s.total += n
	}
	s.active, s.invited = cs.by_status[.Active], cs.by_status[.Invited]
	if s.total > 0 {
		s.avg_score = cs.score_sum / s.total
		s.active_pct = s.active * 100 / s.total
		s.invited_pct = s.invited * 100 / s.total
	}
	s.by_role = make([]int, len(contacts.Role), context.temp_allocator)
	for n, r in cs.by_role {
		s.by_role[int(r)] = n
	}
	s.spread = make([]int, contacts.SCORE_BANDS, context.temp_allocator)
	for bands in cs.by_score {
		for n, i in bands {
			s.spread[i] += n
		}
	}
	s.spread_active = slice.clone(cs.by_score[.Active][:], context.temp_allocator)
	s.spread_invited = slice.clone(cs.by_score[.Invited][:], context.temp_allocator)
	return
}
