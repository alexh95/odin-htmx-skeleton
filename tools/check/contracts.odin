package main

// ---- contracts: every store and every identity holds its contract ------------------------
//
// A feature's store contract is the proc types its models declare, `Store_X ::
// #type proc(…)`. Each store of the feature, in every family that has one,
// states them as typed constants, `_ : m.Store_X : x`, so a drifted signature
// fails in that store's own package, built or not (LC §3). The check is that
// no type is left without its line. Each identity states `_ :
// authz.Load_Viewer : load_viewer` the same way.

import "core:odin/ast"
import "core:slice"
import "core:strings"

check_contracts :: proc(t: ^Tree) {
	for m in t.pkgs {
		if m.kind != .Models { continue }
		want := contract_types(m)
		if len(want) == 0 { continue }
		for s in t.pkgs {
			if s.kind != .Store || s.feature != m.feature { continue }
			have := stated(t, s, m.path)
			for x in want {
				if !slice.contains(have[:], x) {
					problem("contracts", "app/%s: no `_ : m.%s : <proc>` line, so a drift from %s's contract goes unchecked", s.path, x, m.path)
				}
			}
		}
	}
	for p in t.pkgs {
		if !is_identity(t, p) { continue }
		if !slice.contains(stated(t, p, "platform/authz")[:], "Load_Viewer") {
			problem("contracts", "app/%s: an identity states `_ : authz.Load_Viewer : load_viewer`", p.path)
		}
	}
}

// The models' `Store_*` proc types.
@(private = "file")
contract_types :: proc(m: ^Pkg) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for _, f in m.ast.files {
		for d in f.decls {
			vd, ok := d.derived_stmt.(^ast.Value_Decl)
			if !ok || len(vd.names) != 1 || len(vd.values) != 1 { continue }
			name := ident(vd.names[0])
			if !strings.has_prefix(name, "Store_") { continue }
			v := vd.values[0]
			if h, is := v.derived_expr.(^ast.Helper_Type); is { v = h.type }
			if _, is := v.derived_expr.(^ast.Proc_Type); is { append(&out, name) }
		}
	}
	slice.sort(out[:])
	return out[:]
}

// The types p states as `_ : <alias>.X : …`, for aliases that name `of`.
@(private = "file")
stated :: proc(t: ^Tree, p: ^Pkg, of: string) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for _, f in p.ast.files {
		for d in f.decls {
			vd, ok := d.derived_stmt.(^ast.Value_Decl)
			if !ok || len(vd.names) != 1 || ident(vd.names[0]) != "_" { continue }
			alias, x := selector(vd.type)
			if alias != "" && alias_target(t, p, alias) == of { append(&out, x) }
		}
	}
	return out
}

// An identity: a features/accounts/identity_* package, or a family member a
// profile's build.sh line selects.
@(private = "file")
is_identity :: proc(t: ^Tree, p: ^Pkg) -> bool {
	if p.kind == .Identity { return true }
	for q in profiles(t) {
		if strings.trim_prefix(q.identity, "app/") == p.path { return true }
	}
	return false
}
