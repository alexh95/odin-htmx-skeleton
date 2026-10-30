package password

// ---- platform/password: argon2id, off the loops (L2) -------------------------------------
//
// PLAN §17.1, S0.5, D35. Passwords are argon2id at OWASP's parameters (19 MiB, t = 2, p = 1),
// stored as PHC strings (`$argon2id$v=19$m=19456,t=2,p=1$<salt>$<tag>`, unpadded base64). A
// verify costs a core for 20-30 ms, so on a loop it runs on this package's pool: `submit` a
// `Verify` and its `done` comes back on the loop (workers, F-13's deferred response in the
// handler). Each worker keeps one buffer for argon's memory, so the pool holds threads × 19 MiB
// and allocates nothing per login. An unknown name is verified against a dummy all the same,
// so the answer's time says nothing about which names exist; compares are constant-time.

import "base:runtime"
import "core:crypto"
import "core:crypto/argon2id"
import "core:encoding/base64"
import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

import "../workers"

MIN_LEN :: 10
MAX_LEN :: 256

PARAMS :: argon2id.Parameters{memory_size = 19 * 1024, passes = 2, parallelism = 1}
// A stored hash may name OWASP's small preset (7 MiB, t = 5), the fallback for a tight
// mem_limit; nothing else is derived, so a stored string can't ask for any cost.
@(private)
SMALL :: argon2id.Parameters{memory_size = 7 * 1024, passes = 5, parallelism = 1}

SALT_LEN :: 16
TAG_LEN :: 32

// argon's memory plus its own bookkeeping, the most either preset asks for.
@(private)
BUF_LEN :: 19 * 1024 * 1024 + 64 * 1024

Check :: enum u8 {
	Ok,
	Too_Short,
	Too_Long,
}

// The length rule a new password meets (in bytes, as stored); the views say it in words.
check :: proc(pw: string) -> Check {
	switch {
	case len(pw) < MIN_LEN: return .Too_Short
	case len(pw) > MAX_LEN: return .Too_Long
	}
	return .Ok
}

// A fresh PHC string for `pw`, in `allocator`. Blocking (20-30 ms): for the CLI, boot and a
// pool task, never a loop.
hash :: proc(pw: string, allocator := context.allocator) -> string {
	salt: [SALT_LEN]byte
	crypto.rand_bytes(salt[:])
	tag: [TAG_LEN]byte
	p := PARAMS
	derive(&p, pw, salt[:], tag[:])
	return encode(p, salt[:], tag[:], allocator)
}

// Whether `pw` is the password `phc` was made from. Blocking, as `hash`. A string that doesn't
// parse (or names other parameters) is false, after a dummy derive of the same cost.
verify :: proc(pw: string, phc: string) -> bool {
	p, salt, want, ok := decode(phc)
	if !ok || len(pw) > MAX_LEN {
		dummy(pw)
		return false
	}
	got: [TAG_LEN]byte
	derive(&p, pw, salt[:], got[:])
	return crypto.compare_constant_time(got[:], want[:]) == 1
}

// A derive at the default cost whose result is thrown away: what an unknown name costs.
dummy :: proc(pw: string) {
	salt: [SALT_LEN]byte
	tag: [TAG_LEN]byte
	p := PARAMS
	derive(&p, pw[:min(len(pw), MAX_LEN)], salt[:], tag[:])
}

// ---- the pool --------------------------------------------------------------------------

// Embed first: `done` gets it back as the task.
//   Login :: struct { using verify: password.Verify, ref: …, user_id: i64 }
Verify :: struct {
	using task: workers.Task,
	pw:         [MAX_LEN]byte,
	pw_len:     int,
	phc:        [160]byte, // "" for an unknown name: verified against the dummy
	phc_len:    int,
	ok:         bool, // the answer, set by run
}

pool: workers.Pool

// At boot: ACCOUNTS_ARGON_THREADS workers (1 with ≤ 2 CPUs, else 2, Q34) and a queue of 32;
// past it `submit` refuses and the handler answers 503.
start :: proc(threads: int, queue_cap := 32) {
	workers.start(&pool, "argon", threads, queue_cap)
}

// Fills `v` (copies: the request's memory may be gone when the worker runs) and queues it.
// false: the pool is full or draining; answer 503, `done` won't run.
submit :: proc(v: ^Verify, pw, phc: string, done: proc(t: ^workers.Task)) -> bool {
	v.pw_len = copy(v.pw[:], pw)
	v.phc_len = copy(v.phc[:], phc) if len(phc) <= len(v.phc) else 0
	v.ok = false
	v.run = run_verify
	v.done = done
	return workers.submit(&pool, &v.task)
}

@(private)
run_verify :: proc(t: ^workers.Task) {
	v := (^Verify)(t)
	pw := string(v.pw[:v.pw_len])
	if v.phc_len == 0 {
		dummy(pw)
		v.ok = false
	} else {
		v.ok = verify(pw, string(v.phc[:v.phc_len]))
	}
	mem.zero_slice(v.pw[:])
}

// ---- argon and PHC -------------------------------------------------------------------------

// One buffer per thread, taken once and kept: argon allocates its blocks from an arena over it.
@(private, thread_local)
buffer: []byte

@(private)
derive :: proc(p: ^argon2id.Parameters, pw: string, salt, dst: []byte) {
	if buffer == nil { buffer = make([]byte, BUF_LEN, runtime.heap_allocator()) }
	arena: mem.Arena
	mem.arena_init(&arena, buffer)
	err := argon2id.derive(p, transmute([]byte)pw, salt, dst, allocator = mem.arena_allocator(&arena))
	assert(err == nil) // the buffer is sized for the largest preset
}

@(private)
encode :: proc(p: argon2id.Parameters, salt, tag: []byte, allocator: runtime.Allocator) -> string {
	enc := base64.ENC_TABLE
	s := base64.encode(salt, enc, context.temp_allocator)
	t := base64.encode(tag, enc, context.temp_allocator)
	return fmt.aprintf("$argon2id$v=19$m=%d,t=%d,p=%d$%s$%s", p.memory_size, p.passes, p.parallelism,
		strings.trim_right(s, "="), strings.trim_right(t, "="), allocator = allocator)
}

// A PHC string this package made: v=19, one of the two presets, a 16-byte salt and a 32-byte tag.
decode :: proc(phc: string) -> (p: argon2id.Parameters, salt: [SALT_LEN]byte, tag: [TAG_LEN]byte, ok: bool) {
	rest := phc
	parts: [6]string
	n := 0
	for part in strings.split_iterator(&rest, "$") {
		if n == len(parts) { return }
		parts[n] = part
		n += 1
	}
	if n != 6 || parts[0] != "" || parts[1] != "argon2id" || parts[2] != "v=19" { return }
	params := parts[3]
	for kv in strings.split_iterator(&params, ",") {
		k, _, v := strings.partition(kv, "=")
		x, xok := strconv.parse_uint(v, 10)
		if !xok || x > 1 << 32 - 1 { return }
		switch k {
		case "m": p.memory_size = u32(x)
		case "t": p.passes = u32(x)
		case "p": p.parallelism = u32(x)
		case:     return
		}
	}
	if p != PARAMS && p != SMALL { return }
	unb64(parts[4], salt[:]) or_return
	unb64(parts[5], tag[:]) or_return
	return p, salt, tag, true
}

// Unpadded base64 of exactly len(out) bytes.
@(private)
unb64 :: proc(s: string, out: []byte) -> bool {
	want := (len(out) * 4 + 2) / 3
	if len(s) != want { return false }
	pads := "=="
	padded := strings.concatenate({s, pads[:(4 - len(s) % 4) % 4]}, context.temp_allocator)
	b, err := base64.decode(padded, base64.DEC_TABLE, allocator = context.temp_allocator)
	if err != nil || len(b) != len(out) { return false }
	copy(out, b)
	return true
}
