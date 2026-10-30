package main

// ---- the catalog: features, families and profiles, read from the tree ---------------------
//
// Nothing here is declared for the generator's sake. A feature is a directory under
// app/features; what it brings to a profile is what its web package declares (ROUTES, EXTS,
// TOPICS, JOBS, BUNDLES, init, home_card); its dependencies are its packages' imports of
// other features (PLAN §7.4); its stores are the app/stores/<family>/<f> that exist. The
// lines a profile writes for it (a mount, an init call, a nav entry, the copy its init
// takes) come from a committed profile that already mounts it, its donor: those files are
// hand-written and CI holds them to tools/check profile, and every feature is mounted by
// one, since check refuses a ROUTES table no profile mounts.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

Feature :: struct {
	name:       string,
	web:        ^Pkg, // nil when it has no web package
	deps:       [dynamic]string,
	stores:     [dynamic]string, // the store families it has a store in
	uses_store: bool,            // a package of it imports store:<f>
	migrations: bool,            // its SQLite store declares MIGRATIONS
	decls:      bit_set[Web_Decl],
	switched:   [dynamic]string, // features/f/<axis>_<impl>
	lines:      int,
	profiles:   [dynamic]string, // the committed profiles that mount it
	gated:      bool,            // a ROUTES row asks for a permission: it needs an identity on its host
}

Web_Decl :: enum {
	Routes,
	Exts,
	Topics,
	Jobs,
	Bundles,
	Init,
	Home_Card,
}

WEB_DECL_NAMES := [Web_Decl]string {
	.Routes    = "ROUTES",
	.Exts      = "EXTS",
	.Topics    = "TOPICS",
	.Jobs      = "JOBS",
	.Bundles   = "BUNDLES",
	.Init      = "init",
	.Home_Card = "home_card",
}

Family :: enum {
	Store,
	Identity,
	Client,
	Theme,
}

FAMILY_FLAGS := [Family]string {
	.Store    = "store",
	.Identity = "identity",
	.Client   = "client",
	.Theme    = "theme",
}

// A family member: its name on the command line and its directory under app/.
Member :: struct {
	name, dir: string,
	sqlite:    bool, // an identity that reaches its feature's SQLite-only domain (identity_accounts)
	deps:      [dynamic]string, // the features an identity reaches itself (identity_accounts: audit), not its feature's
	topics:    bool,            // an identity with member topics of its own (identity_accounts): the hub is mounted
}

Catalog :: struct {
	tree:     Tree,
	features: [dynamic]Feature,
	members:  [Family][dynamic]Member,
	profiles: [dynamic]Profile,
}

catalog: Catalog

feature :: proc(name: string) -> ^Feature {
	for &f in catalog.features {
		if f.name == name { return &f }
	}
	return nil
}

member :: proc(fam: Family, name: string) -> (Member, bool) {
	for m in catalog.members[fam] {
		if m.name == name { return m, true }
	}
	return {}, false
}

member_by_dir :: proc(fam: Family, dir: string) -> Member {
	for m in catalog.members[fam] {
		if m.dir == dir { return m }
	}
	return {name = dir, dir = dir}
}

load_catalog :: proc(root: string) {
	catalog = {}
	catalog.tree = load_tree(root)
	t := &catalog.tree
	app := join(root, "app")

	for name in subdirs(join(app, "stores")) {
		append(&catalog.members[.Store], Member{name = name, dir = join("stores", name)})
	}
	append(&catalog.members[.Identity], Member{name = "anonymous", dir = "platform/authz/anonymous"})
	for name in subdirs(join(app, "platform/client")) {
		append(&catalog.members[.Client], Member{name = name, dir = join("platform/client", name)})
	}
	for name in subdirs(join(app, "platform/theme")) {
		append(&catalog.members[.Theme], Member{name = name, dir = join("platform/theme", name)})
	}

	for name in subdirs(join(app, "features")) {
		f := Feature{name = name}
		f.web = t.by_path[strings.concatenate({"features/", name, "/web"})]
		f.gated = gated(f.web)
		for d in Web_Decl {
			found := declares_proc(f.web, WEB_DECL_NAMES[d]) if d == .Init || d == .Home_Card else has_decl(f.web, WEB_DECL_NAMES[d])
			if found { f.decls += {d} }
		}
		domain_store := false
		for p in t.pkgs {
			if p.feature != name { continue }
			f.lines += p.lines
			if p.family != "" {
				append(&f.stores, p.family)
				if p.family == "sqlite" && has_decl(p, "MIGRATIONS") { f.migrations = true }
				continue
			}
			rest := strings.trim_prefix(p.path, strings.concatenate({"features/", name}))
			if sub := strings.trim_prefix(rest, "/"); sub != "" && !slice.contains([]string{"models", "views", "web", "storetest"}, sub) {
				if strings.has_prefix(sub, "identity_") {
					append(&catalog.members[.Identity], Member{name = strings.trim_prefix(sub, "identity_"), dir = p.path, topics = has_decl(p, "TOPICS")})
				} else {
					append(&f.switched, sub)
				}
			}
			// An identity member's store is the member's need, not the feature's: `nick` needs none
			// where `identity_accounts` needs SQLite, so a memory profile may mount accounts for nick.
			// A feature with no web package is reached only through its identities, so its
			// domain's store is theirs too.
			member := strings.has_prefix(strings.trim_prefix(rest, "/"), "identity_")
			for imp in p.imports {
				g := feature_of_target(imp.target)
				if g == name && strings.has_prefix(imp.target, "store:") && !member {
					if f.web == nil && rest == "" { domain_store = true } else { f.uses_store = true }
				}
				if g == "" || g == name { continue }
				deps := &f.deps
				if member {
					// The member was registered above, from this same package.
					for &mb in catalog.members[.Identity] {
						if mb.dir == p.path { deps = &mb.deps }
					}
				}
				if !slice.contains(deps[:], g) { append(deps, g) }
			}
		}
		if domain_store && !slice.contains(f.stores[:], "memory") {
			domain := strings.concatenate({"features/", name})
			for &mb in catalog.members[.Identity] {
				p := t.by_path[mb.dir]
				if p == nil || p.feature != name { continue }
				for imp in p.imports {
					if imp.target == domain { mb.sqlite = true }
				}
			}
		}
		append(&catalog.features, f)
	}
	read_profiles(root)
	for p in catalog.profiles {
		for f in p.features {
			if ft := feature(f); ft != nil { append(&ft.profiles, p.name) }
		}
	}
}

@(private = "file")
has_decl :: proc(p: ^Pkg, name: string) -> bool {
	_, ok := decl(p, name)
	return ok
}

subdirs :: proc(dir: string) -> []string {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil { return nil }
	out := make([dynamic]string)
	for e in entries {
		if e.type == .Directory { append(&out, strings.clone(e.name)) }
	}
	slice.sort(out[:])
	return out[:]
}

// Dependencies first, then the rest in the order given; a cycle is a problem.
closure :: proc(names: []string) -> []string {
	out := make([dynamic]string)
	visiting := make(map[string]bool, context.temp_allocator)
	visit :: proc(name: string, out: ^[dynamic]string, visiting: ^map[string]bool) {
		if slice.contains(out[:], name) { return }
		f := feature(name)
		if f == nil {
			problem("no feature %q (odin run tools/init -- --list)", name)
			return
		}
		if visiting[name] {
			problem("%s depends on itself through its imports", name)
			return
		}
		visiting[name] = true
		for d in f.deps { visit(d, out, visiting) }
		append(out, name)
	}
	for n in names { visit(n, &out, &visiting) }
	return out[:]
}

// ---- --list --------------------------------------------------------------------------------

// What --list prints and docs/catalog.json holds. Sizes are rounded to a hundred lines, so the
// committed file changes when a feature grows, not with every edit.
list :: proc(as_json: bool) {
	b := strings.builder_make()
	if !as_json {
		fmt.sbprintln(&b, "features:")
		for f in catalog.features {
			fmt.sbprintf(&b, "  %-10s ~%d lines  stores %s", f.name, round_lines(f.lines), stores_text(f))
			if len(f.deps) > 0 { fmt.sbprintf(&b, "  needs %s", strings.join(f.deps[:], ", ", context.temp_allocator)) }
			if len(f.switched) > 0 { fmt.sbprintf(&b, "  switched %s", strings.join(f.switched[:], ", ", context.temp_allocator)) }
			fmt.sbprintf(&b, "  in %s\n", strings.join(f.profiles[:], ", ", context.temp_allocator) if len(f.profiles) > 0 else "no profile")
		}
		fmt.sbprintln(&b, "families:")
		for fam in Family {
			names := make([dynamic]string, context.temp_allocator)
			for m in catalog.members[fam] { append(&names, m.name) }
			fmt.sbprintf(&b, "  --%-9s %s\n", FAMILY_FLAGS[fam], strings.join(names[:], ", ", context.temp_allocator))
		}
		fmt.sbprintln(&b, "profiles:")
		for p in catalog.profiles {
			fmt.sbprintf(&b, "  %-10s %s  (store=%s identity=%s client=%s theme=%s)\n", p.name,
				strings.join(p.features[:], ", ", context.temp_allocator), p.members[.Store], p.members[.Identity], p.members[.Client], p.members[.Theme])
		}
		fmt.print(strings.to_string(b))
		return
	}
	w :: strings.write_string
	w(&b, "{\n  \"features\": [\n")
	for f, i in catalog.features {
		fmt.sbprintf(&b, "    {{\"name\": %q, \"lines\": %d, \"stores\": %s, \"sqlite\": %q, \"deps\": %s, \"switched\": %s, \"declares\": %s, \"profiles\": %s}}%s\n",
			f.name, round_lines(f.lines), json_list(f.stores[:]), sqlite_need(f), json_list(f.deps[:]), json_list(f.switched[:]),
			json_list(decl_names(f)), json_list(f.profiles[:]), "," if i < len(catalog.features) - 1 else "")
	}
	w(&b, "  ],\n  \"families\": {\n")
	for fam in Family {
		names := make([dynamic]string, context.temp_allocator)
		for m in catalog.members[fam] { append(&names, m.name) }
		fmt.sbprintf(&b, "    %q: %s%s\n", FAMILY_FLAGS[fam], json_list(names[:]), "," if fam != .Theme else "")
	}
	w(&b, "  },\n  \"profiles\": [\n")
	for p, i in catalog.profiles {
		fmt.sbprintf(&b, "    {{\"name\": %q, \"store\": %q, \"identity\": %q, \"client\": %q, \"theme\": %q, \"features\": %s}}%s\n",
			p.name, p.members[.Store], p.members[.Identity], p.members[.Client], p.members[.Theme], json_list(p.features[:]),
			"," if i < len(catalog.profiles) - 1 else "")
	}
	w(&b, "  ]\n}\n")
	fmt.print(strings.to_string(b))
}

round_lines :: proc(n: int) -> int {
	return max(100, (n + 50) / 100 * 100)
}

// "none" (no store), "any" (one in each family), "required" (SQLite only) or "never" (memory only).
sqlite_need :: proc(f: Feature) -> string {
	// Stores no package of the feature imports (yet, or only its identity members do) ask nothing.
	if !f.uses_store { return "none" }
	has_sqlite, has_memory := slice.contains(f.stores[:], "sqlite"), slice.contains(f.stores[:], "memory")
	switch {
	case has_sqlite && has_memory: return "any"
	case has_sqlite:               return "required"
	}
	return "never"
}

@(private = "file")
stores_text :: proc(f: Feature) -> string {
	if len(f.stores) == 0 { return "none" }
	return strings.join(f.stores[:], "+", context.temp_allocator)
}

@(private = "file")
decl_names :: proc(f: Feature) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	for d in Web_Decl {
		if d in f.decls { append(&out, WEB_DECL_NAMES[d]) }
	}
	return out[:]
}

json_list :: proc(xs: []string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_byte(&b, '[')
	for x, i in xs {
		if i > 0 { strings.write_string(&b, ", ") }
		fmt.sbprintf(&b, "%q", x)
	}
	strings.write_byte(&b, ']')
	return strings.to_string(b)
}
