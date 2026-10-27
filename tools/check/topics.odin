package main

// ---- topics and exts: what main names, against what its hosts mount (PLAN §6.1, §9, §12.1) ----
//
// topics: each TOPICS row's family is its feature's ("lab.feed" is lab's) and
// declared once; every package a host mounts that declares TOPICS is named by
// the profile's hub.mount for that host, and nothing else is; a profile that
// mounts topics calls hub.init; and every family a package publishes to by
// literal name is declared somewhere, so a typo fails here and not as a publish
// the hub drops and counts.
//
// exts: every mounted web package declares EXTS (web.Exts{} for none); main's
// BUNDLE_EXTS names every mounted package that declares EXTS and PAGE_BUNDLES
// every one that declares BUNDLES, and neither names a package no host mounts.
// Boot check 6 compares the bundle with BUNDLE_EXTS; this holds BUNDLE_EXTS to
// the mounts.

import "core:odin/ast"
import "core:slice"
import "core:strings"

check_topics :: proc(t: ^Tree) {
	declared := make(map[string]string, context.temp_allocator) // family → the package declaring it
	for q in t.pkgs {
		if q.kind == .Entry { continue } // a profile's TOPICS is its hub.mount table
		vd, has := decl(q, "TOPICS")
		if !has || len(vd.values) != 1 { continue }
		cl, ok := comp_lit(vd.values[0])
		if !ok { continue }
		for e in cl.elems {
			row, rok := comp_lit(e)
			if !rok { continue }
			family := topic_family(q, row)
			if family == "" {
				problem("topics", "%s: a TOPICS row names its family first, or as `family = …`", where_(row.pos))
				continue
			}
			if prev, dup := declared[family]; dup {
				problem("topics", "%s: the family %q is declared by %s and %s", where_(row.pos), family, prev, q.path)
			} else {
				declared[family] = q.path
			}
			if !strings.has_prefix(family, strings.concatenate({q.feature, "."}, context.temp_allocator)) {
				problem("topics", "%s: %s's family %q is outside its feature's (%s.…)", where_(row.pos), q.path, family, q.feature)
			}
		}
	}

	publishes(t, declared)

	for p in profiles(t) {
		for h in p.hosts {
			named := make(map[string]bool, context.temp_allocator)
			for tm in p.topic_mounts {
				if tm.host != h.name { continue }
				for pkg in tm.pkgs { named[pkg] = true }
			}
			mounted := make(map[string]bool, context.temp_allocator)
			for m in h.mounts {
				for target in mount_pkgs(m) {
					if mounted[target] { continue }
					mounted[target] = true
					q, ok := t.by_path[target]
					if !ok { continue }
					if _, has := decl(q, "TOPICS"); has && !named[target] {
						problem("topics", "%s: host %s mounts %s, whose TOPICS no hub.mount(%q) names", where_(m.pos), h.name, target, h.name)
					}
				}
			}
			for tm in p.topic_mounts {
				if tm.host != h.name { continue }
				for pkg in tm.pkgs {
					if !mounted[pkg] {
						problem("topics", "%s: hub.mount(%q) names %s's TOPICS, but host %s doesn't mount it", where_(tm.pos), tm.host, pkg, h.name)
					}
				}
			}
		}
		for tm in p.topic_mounts {
			found := false
			for h in p.hosts { found ||= h.name == tm.host }
			if !found { problem("topics", "%s: hub.mount(%q): %s has no such host", where_(tm.pos), tm.host, p.name) }
		}
		if len(p.topic_mounts) > 0 && !slice.contains(p.inits[:], "platform/hub") {
			problem("topics", "app/%s/main.odin: %s mounts topics but never calls hub.init", p.pkg.path, p.name)
		}
	}
}

// A row's family: `family = "x.y"`, or its first element as positional; either a
// literal or a constant of the package's own (`USER :: "notify.user"`), which the
// package also builds its topics from.
@(private = "file")
topic_family :: proc(q: ^Pkg, row: ^ast.Comp_Lit) -> string {
	for e in row.elems {
		if fv, ok := e.derived_expr.(^ast.Field_Value); ok {
			if ident(fv.field) == "family" { return family_value(q, fv.value) }
			continue
		}
		return family_value(q, e) // positional: the family comes first
	}
	return ""
}

@(private = "file")
family_value :: proc(q: ^Pkg, e: ^ast.Expr) -> string {
	if s, ok := string_lit(e); ok { return s }
	if name := ident(e); name != "" {
		if vd, ok := decl(q, name); ok && !vd.is_mutable && len(vd.values) == 1 {
			s, _ := string_lit(vd.values[0])
			return s
		}
	}
	return ""
}

// ast.inspect's callback takes no data, so the walk's state is the file's.
@(private = "file") walk_tree: ^Tree
@(private = "file") walk_pkg: ^Pkg
@(private = "file") walk_declared: map[string]string

// Every `hub.publish("<family>[:<key>]", …)` with a literal topic names a declared family.
@(private = "file")
publishes :: proc(t: ^Tree, declared: map[string]string) {
	walk_tree, walk_declared = t, declared
	for q in t.pkgs {
		walk_pkg = q
		for _, f in q.ast.files {
			for d in f.decls {
				ast.inspect(d, proc(n: ^ast.Node) -> bool {
					if n == nil { return true }
					call, ok := n.derived.(^ast.Call_Expr)
					if !ok || len(call.args) == 0 { return true }
					alias, name := selector(call.expr)
					if name != "publish" || alias_target(walk_tree, walk_pkg, alias) != "platform/hub" { return true }
					topic, lit := string_lit(call.args[0])
					if !lit { return true }
					family, _, _ := strings.partition(topic, ":")
					if family not_in walk_declared {
						problem("topics", "%s: %s publishes to %q, which no package's TOPICS declares", where_(call.pos), walk_pkg.path, family)
					}
					return true
				})
			}
		}
	}
}

check_exts :: proc(t: ^Tree) {
	for &p in profiles(t) {
		if p.bundle_exts == nil {
			problem("exts", "app/%s/main.odin: %s declares no BUNDLE_EXTS, which boot check 6 compares with its bundle", p.pkg.path, p.name)
		}
		exts := named_by(t, &p, p.bundle_exts, "EXTS")
		bundles := named_by(t, &p, p.page_bundles, "BUNDLES")
		mounted := make(map[string]bool, context.temp_allocator)
		for h in p.hosts {
			for m in h.mounts {
				for target in mount_pkgs(m) {
					if mounted[target] { continue }
					mounted[target] = true
					q, ok := t.by_path[target]
					if !ok { continue }
					_, has_exts := decl(q, "EXTS")
					_, has_bundles := decl(q, "BUNDLES")
					if q.kind == .Web && !has_exts {
						problem("exts", "%s: %s declares no EXTS (%s when it needs none)", where_(m.pos), target, "web.Exts{}")
					}
					if has_exts && !exts[target] {
						problem("exts", "app/%s/main.odin: BUNDLE_EXTS doesn't name %s, which %s mounts", p.pkg.path, target, p.name)
					}
					if has_bundles && !bundles[target] {
						problem("exts", "app/%s/main.odin: PAGE_BUNDLES doesn't name %s, whose pages load its BUNDLES", p.pkg.path, target)
					}
				}
			}
		}
		for target in exts {
			if !mounted[target] { problem("exts", "app/%s/main.odin: BUNDLE_EXTS names %s, which no host of %s mounts", p.pkg.path, target, p.name) }
		}
		for target in bundles {
			if !mounted[target] { problem("exts", "app/%s/main.odin: PAGE_BUNDLES names %s, which no host of %s mounts", p.pkg.path, target, p.name) }
		}
	}
}

// The packages a mount puts on its host: the table's, or the handlers' of the
// profile's own rows (`{{.Get, "/", home_web.page, …}}` mounts home_web).
@(private = "file")
mount_pkgs :: proc(m: Mount) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	if m.target != "" {
		append(&out, m.target)
		return out[:]
	}
	for r in m.rows {
		if r.handler_pkg != "" { append(&out, r.handler_pkg) }
	}
	return out[:]
}

// The packages an expression names as `<alias>.<field>`: `lab_web.EXTS + about_web.EXTS`.
@(private = "file") named_field: string
@(private = "file") named_aliases: [dynamic]string

@(private = "file")
named_by :: proc(t: ^Tree, p: ^Profile, vd: ^ast.Value_Decl, field: string) -> map[string]bool {
	out := make(map[string]bool, context.temp_allocator)
	if vd == nil || len(vd.values) != 1 { return out }
	named_field = field
	named_aliases = make([dynamic]string, context.temp_allocator)
	ast.inspect(vd.values[0], proc(n: ^ast.Node) -> bool {
		if n == nil { return true }
		if s, ok := n.derived.(^ast.Selector_Expr); ok && s.field.name == named_field { append(&named_aliases, ident(s.expr)) }
		return true
	})
	for a in named_aliases { out[family_member(p, alias_target(t, p.pkg, a))] = true }
	return out
}
