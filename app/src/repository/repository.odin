package repository
import "../models"

import "core:strings"

// ---- repository ---------------------------------------------------------
//
// In-memory store. Owns the data and the id counter; nothing above it touches
// the slice directly. The server runs a single nbio event-loop thread
// (Server_Opts.thread_count = 1 in main), so every handler is serialised onto
// that one thread and the store needs no lock. That is a deliberate choice,
// not an oversight: a mutex here would guard against contention that the
// threading model rules out.
//
// Stored strings live on the heap (context.allocator), independent of the
// per-request temp arena, so a contact created on one request survives the
// next. create/update clone their inputs; delete frees them.

@(private = "file")
Store :: struct {
	contacts: [dynamic]models.Contact,
	next_id:  int,
}

@(private = "file")
store: Store

repo_list :: proc() -> []models.Contact {
	return store.contacts[:]
}

repo_get :: proc(id: int) -> (models.Contact, bool) {
	for c in store.contacts {
		if c.id == id {
			return c, true
		}
	}
	return {}, false
}

repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> models.Contact {
	store.next_id += 1
	c := models.Contact {
		id     = store.next_id,
		name   = strings.clone(name),
		email  = strings.clone(email),
		role   = role,
		status = status,
		score  = score,
	}
	append(&store.contacts, c)
	return c
}

repo_update :: proc(id: int, name, email: string, role: models.Role, status: models.Status) -> (models.Contact, bool) {
	for &c in store.contacts {
		if c.id == id {
			delete(c.name)
			delete(c.email)
			c.name = strings.clone(name)
			c.email = strings.clone(email)
			c.role = role
			c.status = status
			return c, true
		}
	}
	return {}, false
}

repo_set_status :: proc(id: int, status: models.Status) -> (models.Contact, bool) {
	for &c in store.contacts {
		if c.id == id {
			c.status = status
			return c, true
		}
	}
	return {}, false
}

repo_delete :: proc(id: int) -> bool {
	for c, i in store.contacts {
		if c.id == id {
			delete(c.name)
			delete(c.email)
			ordered_remove(&store.contacts, i)
			return true
		}
	}
	return false
}

// Deterministic seed so the demo looks the same on every launch. Names and
// roles are woven from two small tables; the score is a cheap hash of the id
// to spread the progress bars without pulling in core:math/rand.
repo_seed :: proc() {
	firsts := []string {
		"Ada", "Linus", "Grace", "Dennis", "Margaret", "Alan", "Katherine",
		"Edsger", "Barbara", "Donald", "Radia", "Ken", "Hedy", "Tim",
		"Anita", "John", "Carol", "Vint", "Shafi", "Niklaus",
	}
	lasts := []string {
		"Lovelace", "Torvalds", "Hopper", "Ritchie", "Hamilton", "Turing",
		"Johnson", "Dijkstra", "Liskov", "Knuth", "Perlman", "Thompson",
		"Lamarr", "Berners-Lee", "Borg", "Carmack", "Shaw", "Cerf",
		"Goldwasser", "Wirth",
	}

	for i in 0 ..< len(firsts) {
		first := firsts[i]
		last := lasts[i % len(lasts)]
		email := strings.to_lower(
			strings.concatenate({first, ".", last, "@example.dev"}, context.temp_allocator),
			context.temp_allocator,
		)
		role := models.Role((i * 7 + 3) % len(models.Role))
		status := models.Status(i % len(models.Status))
		score := 35 + (i * 53) % 64

		name := strings.concatenate({first, " ", last}, context.temp_allocator)
		repo_create(name, email, role, status, score)
	}
}
