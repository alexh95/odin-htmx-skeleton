package repository
import "../models"

import "core:strings"
import "core:sync"

// ---- repository ---------------------------------------------------------
//
// In-memory store. Owns the data and the id counter; nothing above it touches
// the slice directly. The server now runs N nbio event-loop threads (one per
// core; see main), so handlers execute concurrently and the store is guarded by
// an RW_Mutex: reads share, writes are exclusive. A read-heavy server wants
// readers to run in parallel, which is exactly what the shared lock buys.
//
// The catch with concurrency: callers read the returned contacts *after* the
// proc returns, i.e. after the lock is released — by which point another thread
// may have grown the slice (realloc) or deleted a row (freeing its strings).
// So every contact handed out is a **snapshot**: the structs are copied and the
// name/email are cloned into the caller's temp arena under the lock. Nothing the
// caller holds points back into the store. The clone is a few small bumps in the
// request arena, negligible against building the HTML/JSON response.
//
// Stored strings live on the heap (context.allocator), independent of the
// per-request temp arena, so a contact created on one request survives the next.
// create/update clone their inputs; delete frees them.

@(private = "file")
Store :: struct {
	contacts: [dynamic]models.Contact,
	next_id:  int,
	lock:     sync.RW_Mutex,
}

@(private = "file")
store: Store

// Copy a stored contact into the caller's temp arena: struct by value, strings
// cloned, so it stays valid after the store lock drops and across later writes.
@(private = "file")
snapshot :: proc(c: models.Contact) -> models.Contact {
	out := c
	out.name = strings.clone(c.name, context.temp_allocator)
	out.email = strings.clone(c.email, context.temp_allocator)
	return out
}

repo_list :: proc() -> []models.Contact {
	sync.rw_mutex_shared_lock(&store.lock)
	defer sync.rw_mutex_shared_unlock(&store.lock)
	out := make([]models.Contact, len(store.contacts), context.temp_allocator)
	for c, i in store.contacts {
		out[i] = snapshot(c)
	}
	return out
}

repo_get :: proc(id: int) -> (models.Contact, bool) {
	sync.rw_mutex_shared_lock(&store.lock)
	defer sync.rw_mutex_shared_unlock(&store.lock)
	for c in store.contacts {
		if c.id == id {
			return snapshot(c), true
		}
	}
	return {}, false
}

repo_create :: proc(name, email: string, role: models.Role, status: models.Status, score: int) -> models.Contact {
	sync.rw_mutex_lock(&store.lock)
	defer sync.rw_mutex_unlock(&store.lock)
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
	return snapshot(c)
}

repo_update :: proc(id: int, name, email: string, role: models.Role, status: models.Status) -> (models.Contact, bool) {
	sync.rw_mutex_lock(&store.lock)
	defer sync.rw_mutex_unlock(&store.lock)
	for &c in store.contacts {
		if c.id == id {
			delete(c.name)
			delete(c.email)
			c.name = strings.clone(name)
			c.email = strings.clone(email)
			c.role = role
			c.status = status
			return snapshot(c), true
		}
	}
	return {}, false
}

repo_set_status :: proc(id: int, status: models.Status) -> (models.Contact, bool) {
	sync.rw_mutex_lock(&store.lock)
	defer sync.rw_mutex_unlock(&store.lock)
	for &c in store.contacts {
		if c.id == id {
			c.status = status
			return snapshot(c), true
		}
	}
	return {}, false
}

repo_delete :: proc(id: int) -> bool {
	sync.rw_mutex_lock(&store.lock)
	defer sync.rw_mutex_unlock(&store.lock)
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
