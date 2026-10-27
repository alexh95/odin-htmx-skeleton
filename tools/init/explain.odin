package main

// ---- the plan, printed: what a run would compose, before it asks ----------------------------

import "core:fmt"
import "core:odin/ast"
import "core:slice"
import "core:strings"

print_plan :: proc(s: Selection, text: Profile_Text) {
	fmt.printfln("plan for %q", s.name)
	named := make([dynamic]string, context.temp_allocator)
	for f in s.features {
		why := ""
		if f == s.root { why = " (the root)" }
		if !asked(s, f) && f != s.root {
			needers := make([dynamic]string, context.temp_allocator)
			for g in s.features {
				if gf := feature(g); gf != nil && slice.contains(gf.deps[:], f) { append(&needers, g) }
			}
			why = fmt.tprintf(" (a dependency of %s)", strings.join(needers[:], ", ", context.temp_allocator))
		}
		append(&named, fmt.tprintf("%s%s", f, why))
	}
	row("features", strings.join(named[:], ", ", context.temp_allocator))
	row("families", fmt.tprintf("store=%s  identity=%s  client=%s  theme=%s", s.members[.Store], s.members[.Identity], s.members[.Client], s.members[.Theme]))
	switched := make([dynamic]string, context.temp_allocator)
	stores := make([dynamic]string, context.temp_allocator)
	exts := make([dynamic]string, context.temp_allocator)
	topics := make([dynamic]string, context.temp_allocator)
	migrations := make([dynamic]string, context.temp_allocator)
	routes := make([dynamic]string, context.temp_allocator)
	total := 0
	for f in s.features {
		ft := feature(f)
		if ft == nil { continue }
		for x in ft.switched { append(&switched, fmt.tprintf("%s.%s", f, x)) }
		if slice.contains(ft.stores[:], s.members[.Store]) { append(&stores, f) }
		for e in set_members(ft.web, "EXTS") {
			if !slice.contains(exts[:], e) { append(&exts, e) }
		}
		append(&topics, ..topic_families(ft.web))
		if s.members[.Store] == "sqlite" && ft.migrations { append(&migrations, f) }
		if n := row_count(ft.web); n > 0 {
			append(&routes, fmt.tprintf("%s %d", f, n))
			total += n
		}
	}
	if len(switched) > 0 { row("switched", strings.join(switched[:], ", ", context.temp_allocator)) }
	if len(stores) > 0 { row("stores", fmt.tprintf("app/stores/%s/{{%s}}", s.members[.Store], strings.join(stores[:], ", ", context.temp_allocator))) }
	row("sqlite", "the store family: prepare builds the SQLite library" if s.members[.Store] == "sqlite" else "none: the build links no SQLite library")
	row("bundle", strings.concatenate({"htmx", " + " if len(exts) > 0 else "", strings.join(exts[:], ", ", context.temp_allocator)}, context.temp_allocator))
	row("hosts", fmt.tprintf("main: %d routes (%s), the root %s", total, strings.join(routes[:], ", ", context.temp_allocator), s.root))
	if len(topics) > 0 { row("topics", strings.join(topics[:], ", ", context.temp_allocator)) }
	if len(migrations) > 0 { row("migrations", fmt.tprintf("%s (one migrate line each in main, in dependency order)", strings.join(migrations[:], ", ", context.temp_allocator))) }
	donors := make([dynamic]string, context.temp_allocator)
	for f in s.features {
		if d := donor(s, f); d != nil { append(&donors, fmt.tprintf("%s from %s", f, d.name)) }
	}
	row("lines", strings.join(donors[:], ", ", context.temp_allocator))
	for n in text.notes { row("check", n) }
}

@(private = "file")
row :: proc(label, value: string) {
	fmt.printfln("  %-11s %s", label, value)
}

// Whether the feature was asked for (named, or in --profile's selection), not pulled in.
@(private = "file")
asked :: proc(s: Selection, f: string) -> bool {
	for g in s.features {
		if gf := feature(g); gf != nil && slice.contains(gf.deps[:], f) { return false }
	}
	return true
}

// `X :: web.Exts{.Sse, .Ws}` → {"sse", "ws"}.
set_members :: proc(p: ^Pkg, name: string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	vd, ok := decl(p, name)
	if !ok || len(vd.values) != 1 { return out[:] }
	cl, is := comp_lit(vd.values[0])
	if !is { return out[:] }
	for e in cl.elems {
		if is_sel, iok := e.derived_expr.(^ast.Implicit_Selector_Expr); iok { append(&out, strings.to_lower(is_sel.field.name)) }
	}
	return out[:]
}

// The families a web package's TOPICS declares.
topic_families :: proc(p: ^Pkg) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	vd, ok := decl(p, "TOPICS")
	if !ok || len(vd.values) != 1 { return out[:] }
	cl, is := comp_lit(vd.values[0])
	if !is { return out[:] }
	for e in cl.elems {
		t, tc := comp_lit(e)
		if !tc { continue }
		for fe in t.elems {
			fv, fok := fe.derived_expr.(^ast.Field_Value)
			if !fok || ident(fv.field) != "family" { continue }
			if fam, _ := string_lit(fv.value); fam != "" { append(&out, fam) }
		}
	}
	return out[:]
}

// The rows of a web package's ROUTES.
row_count :: proc(p: ^Pkg) -> int {
	vd, ok := decl(p, "ROUTES")
	if !ok || len(vd.values) != 1 { return 0 }
	cl, is := comp_lit(vd.values[0])
	return len(cl.elems) if is else 0
}
