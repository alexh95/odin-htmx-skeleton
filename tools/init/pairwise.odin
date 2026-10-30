package main

// ---- the nightly selections: a covering array and seeded random ones (PLAN §19.1.12, D37, D44) --
//
// `--pairwise --seed <n>` prints rows of features whose presence covers every pair of feature
// presence values (both present, both absent, one without the other) that any valid selection
// can cover; `--random --seed <n>` prints one random valid selection. Valid is what `select`
// accepts, plus the one rule it doesn't hold: a generated project has a single host and so one
// root, so `dashboard` and `landing` never meet (§7.4). `home` is no factor: it joins exactly when
// neither does. A row is its closed selection (dependencies and identities brought in), so the
// pairs it covers are the ones a build of it really has. The generator is our own xorshift, so
// a seed means the same rows on every machine and Odin version; `.github/matrix/pairwise.json` is
// seed 1's, and CI holds it current.

import "core:fmt"
import "core:slice"
import "core:strings"

@(private = "file")
Rng :: struct {
	s: u64,
}

@(private = "file")
next :: proc(r: ^Rng) -> u64 {
	r.s ~= r.s << 13
	r.s ~= r.s >> 7
	r.s ~= r.s << 17
	return r.s
}

@(private = "file")
factors :: proc() -> []string {
	out := make([dynamic]string)
	for f in catalog.features {
		if f.name != "home" { append(&out, f.name) }
	}
	return out[:]
}

// The closed selection `want` becomes, or nil when it can't build.
@(private = "file")
valid :: proc(want: []string) -> []string {
	if len(want) == 0 { return nil }
	if slice.contains(want, "dashboard") && slice.contains(want, "landing") { return nil }
	clear(&problems)
	s := select("app", "", want, {})
	ok := len(problems) == 0
	clear(&problems)
	if !ok { return nil }
	if slice.contains(s.features, "dashboard") && slice.contains(s.features, "landing") { return nil }
	return s.features
}

// A random selection, each factor in with probability one half, `fixed` (index → presence) kept.
@(private = "file")
draw :: proc(r: ^Rng, fs: []string, fixed: map[int]bool) -> []string {
	out := make([dynamic]string)
	for f, i in fs {
		in_, set := fixed[i]
		if !set { in_ = next(r) & 1 == 1 }
		if in_ { append(&out, f) }
	}
	return out[:]
}

@(private = "file")
Pair :: struct {
	a, b:   int,
	va, vb: bool,
}

@(private = "file")
covers :: proc(row: []string, fs: []string, p: Pair) -> bool {
	return slice.contains(row, fs[p.a]) == p.va && slice.contains(row, fs[p.b]) == p.vb
}

// The covering array as JSON: {"seed", "rows": [{"name", "features"}], "infeasible": [pairs]}.
pairwise :: proc(seed: u64) {
	r := Rng{seed * 0x9E3779B97F4A7C15 | 1}
	fs := factors()
	left := make([dynamic]Pair)
	for a in 0 ..< len(fs) {
		for b in a + 1 ..< len(fs) {
			for v in 0 ..< 4 { append(&left, Pair{a, b, v & 1 == 1, v & 2 == 2}) }
		}
	}
	rows := make([dynamic][]string)
	infeasible := make([dynamic]Pair)
	CANDIDATES :: 400
	for len(left) > 0 {
		// The candidate that covers the most pairs still left; the first pair left is forced in, so
		// every round either covers it or finds it can't be.
		first := left[0]
		fixed := make(map[int]bool, context.temp_allocator)
		fixed[first.a], fixed[first.b] = first.va, first.vb
		best: []string
		best_n := 0
		for _ in 0 ..< CANDIDATES {
			row := valid(draw(&r, fs, fixed))
			if row == nil || !covers(row, fs, first) { continue }
			n := 0
			for p in left { if covers(row, fs, p) { n += 1 } }
			if n > best_n { best, best_n = row, n }
		}
		if best == nil {
			append(&infeasible, first)
			ordered_remove(&left, 0)
			continue
		}
		append(&rows, best)
		kept := make([dynamic]Pair)
		for p in left { if !covers(best, fs, p) { append(&kept, p) } }
		left = kept
	}

	b := strings.builder_make()
	fmt.sbprintf(&b, "{{\n\t\"seed\": %d,\n\t\"rows\": [\n", seed)
	for row, i in rows {
		fmt.sbprintf(&b, "\t\t{{\"name\": \"pairwise-%d\", \"features\": \"%s\"}}%s\n", i + 1, strings.join(row, ","), "," if i < len(rows) - 1 else "")
	}
	strings.write_string(&b, "\t],\n\t\"infeasible\": [\n")
	for p, i in infeasible {
		fmt.sbprintf(&b, "\t\t\"%s%s %s%s\"%s\n", "" if p.va else "!", fs[p.a], "" if p.vb else "!", fs[p.b], "," if i < len(infeasible) - 1 else "")
	}
	strings.write_string(&b, "\t]\n}\n")
	fmt.print(strings.to_string(b))
}

// One random valid selection's features, comma-separated (what --features takes).
random_selection :: proc(seed: u64) {
	r := Rng{seed * 0x9E3779B97F4A7C15 | 1}
	fs := factors()
	for _ in 0 ..< 10_000 {
		if row := valid(draw(&r, fs, nil)); row != nil {
			fmt.println(strings.join(row, ","))
			return
		}
	}
	fatal("no valid selection in 10000 draws")
}
