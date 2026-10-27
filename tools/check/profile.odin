package main

// ---- profile and routes: the four hand-written files, read back -------------------------
//
// A profile is app/cmd/<p>/ plus its line in build.sh, which names its family
// members. routes.odin's tables are package-level `[?]app.Mount{{"<feature>",
// <rows>}, …}` and `[?]app.Host{{name, env, identity, <table>[:], <nav>[:]}}`;
// a mount's rows are a package's table (`contacts_web.ROUTES[:]`) or the
// profile's own (`{{.Get, "/", dashboard_web.page, …}}`). main.odin's calls
// are read from its `main` proc: `<alias>.init(…)`,
// `store_sqlite.migrate("<f>", <alias>.MIGRATIONS[:])` and
// `hub.mount("<host>", ..<table>[:])`; and its BUNDLE_EXTS and PAGE_BUNDLES.

import "core:odin/ast"
import "core:os"
import "core:slice"
import "core:strings"
import "core:odin/tokenizer"

Row :: struct {
	method, pattern: string,
	owner:           string, // the feature whose prefixes it must sit in
	inline:          bool,   // written in the profile, not in a package's table
	handler_pkg:     string, // an inline row's handler's package: it is mounted too
	pos:             tokenizer.Pos,
}

Mount :: struct {
	feature: string,
	target:  string, // the mounted table's package; "" for the profile's own rows
	table:   string, // the mounted table's name: ROUTES, PUBLIC_ROUTES …
	rows:    [dynamic]Row,
	pos:     tokenizer.Pos,
}

Host :: struct {
	name:   string,
	mounts: [dynamic]Mount,
}

Profile :: struct {
	name:                          string,
	store, identity, client, theme: string, // build.sh's families
	pkg:                           ^Pkg,
	hosts:                         [dynamic]Host,
	inits:                         [dynamic]string, // the targets whose init main calls
	migrates:                      [dynamic]Migrate,
	topic_mounts:                  [dynamic]Topic_Mount, // main's hub.mount calls
	bundle_exts, page_bundles:     ^ast.Value_Decl,      // main's BUNDLE_EXTS and PAGE_BUNDLES; nil if none
}

// `hub.mount("<host>", ..<table>[:])` in main: the host, and the packages whose
// TOPICS the profile's `[?][]hub.Topic` table lists.
Topic_Mount :: struct {
	host:  string,
	table: string,
	pkgs:  [dynamic]string,
	pos:   tokenizer.Pos,
}

Migrate :: struct {
	feature, target: string,
	pos:             tokenizer.Pos,
}

// Every profile build.sh names, read once; nil when build.sh is missing.
profiles_cache: [dynamic]Profile
profiles_read: bool

profiles :: proc(t: ^Tree) -> []Profile {
	if profiles_read { return profiles_cache[:] }
	profiles_read = true
	data, err := os.read_entire_file(strings.concatenate({t.root, "/build.sh"}), context.allocator)
	if err != nil {
		problem("profile", "no build.sh at the root: the profiles' families live there")
		return nil
	}
	// `  skeleton) store=sqlite id=platform/authz/anonymous client=vanilla theme=full ;;`
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		l := strings.trim_space(line)
		paren := strings.index_byte(l, ')')
		if paren <= 0 || !strings.contains(l, "store=") { continue }
		p := Profile{name = l[:paren]}
		for kv in strings.fields(l[paren + 1:]) {
			k, _, v := strings.partition(kv, "=")
			switch k {
			case "store":  p.store = v
			case "id":     p.identity = v
			case "client": p.client = v
			case "theme":  p.theme = v
			}
		}
		pkg, ok := t.by_path[strings.concatenate({"cmd/", p.name})]
		if !ok {
			problem("profile", "build.sh names %s, but there's no app/cmd/%s", p.name, p.name)
			continue
		}
		p.pkg = pkg
		read_profile(t, &p)
		append(&profiles_cache, p)
	}
	for q in t.pkgs {
		if q.kind != .Entry { continue }
		named := false
		for p in profiles_cache { named ||= p.pkg == q }
		if !named { problem("profile", "app/%s has no line in build.sh, so nothing builds it", q.path) }
	}
	return profiles_cache[:]
}

@(private = "file")
read_profile :: proc(t: ^Tree, p: ^Profile) {
	tables := make(map[string][dynamic]Mount, context.allocator)
	host_decls := make([dynamic]^ast.Comp_Lit, context.allocator)
	for _, f in p.pkg.ast.files {
		for d in f.decls {
			vd, ok := d.derived_stmt.(^ast.Value_Decl)
			if !ok || len(vd.values) != 1 || len(vd.names) != 1 { continue }
			if pl, is_proc := vd.values[0].derived_expr.(^ast.Proc_Lit); is_proc {
				if ident(vd.names[0]) == "main" { read_main(t, p, pl) }
				continue
			}
			switch ident(vd.names[0]) {
			case "BUNDLE_EXTS":  p.bundle_exts = vd
			case "PAGE_BUNDLES": p.page_bundles = vd
			}
			cl, is := comp_lit(vd.values[0])
			if !is { continue }
			switch comp_elem_type(cl) {
			case "app.Mount": tables[ident(vd.names[0])] = read_mounts(t, p, cl)
			case "app.Host":  for e in cl.elems { if h, hc := comp_lit(e); hc { append(&host_decls, h) } }
			}
		}
	}
	for h in host_decls {
		// {name, site_env, identity, routes[:], nav[:]}
		if len(h.elems) < 4 {
			problem("profile", "%s: a host needs {name, site env, identity, routes, …}", where_(h.pos))
			continue
		}
		name, _ := string_lit(h.elems[0])
		table := ident(sliced(h.elems[3]))
		mounts, ok := tables[table]
		if !ok {
			problem("profile", "%s: host %s mounts %q, which isn't a [?]app.Mount table of this profile", where_(h.pos), name, table)
			continue
		}
		append(&p.hosts, Host{name, mounts})
	}
	// Each hub.mount's table: `[?][]hub.Topic{lab_web.TOPICS[:], …}`.
	for &tm in p.topic_mounts {
		cl: ^ast.Comp_Lit
		is := false
		if vd, ok := decl(p.pkg, tm.table); ok && len(vd.values) == 1 { cl, is = comp_lit(vd.values[0]) }
		if !is {
			problem("topics", "%s: hub.mount(%q) takes %q, which isn't a table of this profile", where_(tm.pos), tm.host, tm.table)
			continue
		}
		for e in cl.elems {
			alias, field := selector(sliced(e))
			if field != "TOPICS" {
				problem("topics", "%s: %s holds %s, not a package's TOPICS[:]", where_(e.pos), tm.table, field if field != "" else "an entry")
				continue
			}
			append(&tm.pkgs, alias_target(t, p.pkg, alias))
		}
	}
}

@(private = "file")
read_mounts :: proc(t: ^Tree, p: ^Profile, cl: ^ast.Comp_Lit) -> [dynamic]Mount {
	out := make([dynamic]Mount)
	for e in cl.elems {
		m, ok := comp_lit(e)
		if !ok || len(m.elems) != 2 {
			problem("profile", "%s: a mount is {\"<feature>\", <rows>}", where_(e.pos))
			continue
		}
		feature, _ := string_lit(m.elems[0])
		mount := Mount{feature = feature, pos = m.pos}
		if inner := sliced(m.elems[1]); inner != nil {
			alias, table := selector(inner)
			mount.target, mount.table = alias_target(t, p.pkg, alias), table
			if q, has := t.by_path[mount.target]; has {
				if vd, found := decl(q, table); found && len(vd.values) == 1 {
					if rows, rok := comp_lit(vd.values[0]); rok { read_rows(t, q, rows, &mount, false) }
				} else {
					problem("profile", "%s: %s has no %s table", where_(m.pos), mount.target, table)
				}
			} else {
				problem("profile", "%s: %q mounts %s.%s, which isn't an imported app package", where_(m.pos), feature, alias, table)
			}
		} else if rows, rok := comp_lit(m.elems[1]); rok {
			read_rows(t, p.pkg, rows, &mount, true)
		}
		append(&out, mount)
	}
	return out
}

// `{.Get, "/pattern", handler, perm, flags, cap}`: the method and pattern, and
// for the profile's own rows the handler's package, which owns the row.
@(private = "file")
read_rows :: proc(t: ^Tree, in_pkg: ^Pkg, rows: ^ast.Comp_Lit, m: ^Mount, inline: bool) {
	for e in rows.elems {
		r, ok := comp_lit(e)
		if !ok || len(r.elems) < 3 {
			problem("routes", "%s: a route row is {.Method, \"pattern\", handler, …}", where_(e.pos))
			continue
		}
		method := ""
		if is, iok := r.elems[0].derived_expr.(^ast.Implicit_Selector_Expr); iok { method = strings.to_upper(is.field.name) }
		pattern, _ := string_lit(r.elems[1])
		// A package's rows are its feature's, whatever the mount calls them (that
		// mismatch is profile's problem); a profile's own rows are its mount's.
		row := Row{method = method, pattern = pattern, owner = m.feature if inline else in_pkg.feature, inline = inline, pos = r.pos}
		if inline {
			// The handler says whose row it is: a profile row may only mount a
			// handler of the feature its mount names.
			if alias, _ := selector(r.elems[2]); alias != "" {
				if q, has := t.by_path[alias_target(t, in_pkg, alias)]; has {
					row.handler_pkg = q.path
					if q.feature != m.feature {
						problem("profile", "%s: the %q mount's row %s %s is %s's handler", where_(r.pos), m.feature, method, pattern, q.feature)
					}
				}
			}
		}
		append(&m.rows, row)
	}
}

// ast.inspect's callback takes no data, so the walk's state is the file's.
@(private = "file") cur: ^Profile
@(private = "file") tree: ^Tree

@(private = "file")
read_main :: proc(t: ^Tree, p: ^Profile, pl: ^ast.Proc_Lit) {
	cur, tree = p, t
	ast.inspect(pl.body, proc(n: ^ast.Node) -> bool {
		if n == nil { return true } // the end of a node's children
		call, ok := n.derived.(^ast.Call_Expr)
		if !ok { return true }
		alias, name := selector(call.expr)
		switch {
		case name == "init" && alias != "":
			append(&cur.inits, alias_target(tree, cur.pkg, alias))
		case name == "mount" && len(call.args) == 2 && alias_target(tree, cur.pkg, alias) == "platform/hub":
			host, _ := string_lit(call.args[0])
			append(&cur.topic_mounts, Topic_Mount{host = host, table = ident(sliced(call.args[1])), pos = call.pos})
		case name == "migrate" && len(call.args) == 2:
			feature, _ := string_lit(call.args[0])
			a, field := selector(sliced(call.args[1]))
			if field == "MIGRATIONS" {
				append(&cur.migrates, Migrate{feature, alias_target(tree, cur.pkg, a), call.pos})
			}
		}
		return true
	})
}

// ---- profile -------------------------------------------------------------------------

check_profiles :: proc(t: ^Tree) {
	ps := profiles(t)
	mounted := make(map[string]bool, context.temp_allocator) // "<target>.<table>" by any profile
	for &p in ps {
		mounted_here := make(map[string]bool, context.temp_allocator)
		for h in p.hosts {
			for m in h.mounts {
				if m.target == "" { continue }
				key := strings.concatenate({m.target, ".", m.table}, context.temp_allocator)
				mounted[key], mounted_here[m.target] = true, true
				// A mount names the feature whose table it is.
				if q, ok := t.by_path[m.target]; ok && q.feature != m.feature {
					problem("profile", "%s: %s mounts %s.%s as %q; it is %s's", where_(m.pos), p.name, m.target, m.table, m.feature, q.feature)
				}
			}
		}
		// Every web package the profile imports is mounted, and its init called.
		for imp in p.pkg.imports {
			q, ok := t.by_path[imp.target]
			if !ok || q.kind != .Web { continue }
			if _, has := decl(q, "ROUTES"); has && !mounted_here[q.path] {
				problem("profile", "%s: %s imports %s, but no host mounts its ROUTES", where_(imp.node.pos), p.name, q.path)
			}
			if declares_proc(q, "init") && !slice.contains(p.inits[:], q.path) {
				problem("profile", "%s: %s imports %s, which declares init, but main never calls it", where_(imp.node.pos), p.name, q.path)
			}
		}
		check_migrations(t, &p)
	}
	// No ROUTES table that no committed profile mounts.
	for q in t.pkgs {
		if q.kind != .Web { continue }
		if vd, has := decl(q, "ROUTES"); has && !mounted[strings.concatenate({q.path, ".ROUTES"}, context.temp_allocator)] {
			problem("profile", "%s: %s's ROUTES is mounted by no profile", where_(vd.pos), q.path)
		}
	}
}

// A SQLite build migrates every SQLite store it reaches with MIGRATIONS, one
// line each, named by its feature.
@(private = "file")
check_migrations :: proc(t: ^Tree, p: ^Profile) {
	for &m in p.migrates {
		if strings.has_prefix(m.target, "store:") {
			m.target = strings.concatenate({"stores/", p.store, "/", strings.trim_prefix(m.target, "store:")})
		}
		q, ok := t.by_path[m.target]
		if !ok || q.kind != .Store {
			problem("profile", "%s: migrate(%q) names %s, not a store", where_(m.pos), m.feature, m.target)
		} else if q.feature != m.feature {
			problem("profile", "%s: migrate(%q) runs %s's migrations", where_(m.pos), m.feature, q.feature)
		}
	}
	if p.store != "sqlite" { return }
	for path in reached(t, p) {
		q := t.by_path[path]
		if q.kind != .Store { continue }
		if _, has := decl(q, "MIGRATIONS"); !has { continue }
		found := false
		for m in p.migrates { found ||= m.target == path }
		if !found {
			problem("profile", "app/%s/main.odin: %s reaches %s, which has MIGRATIONS, but main never migrates %q", p.pkg.path, p.name, path, q.feature)
		}
	}
}

// Every app package the profile's build reaches, through its imports and its
// families: store:f is app/stores/<store>/f.
reached :: proc(t: ^Tree, p: ^Profile) -> []string {
	seen := make(map[string]bool, context.temp_allocator)
	stack := make([dynamic]string, context.temp_allocator)
	append(&stack, p.pkg.path)
	for len(stack) > 0 {
		path := pop(&stack)
		if seen[path] { continue }
		seen[path] = true
		q, ok := t.by_path[path]
		if !ok { continue }
		for imp in q.imports {
			target := imp.target
			switch {
			case strings.has_prefix(target, "store:"):
				target = strings.concatenate({"stores/", p.store, "/", strings.trim_prefix(target, "store:")}, context.temp_allocator)
				target = strings.trim_suffix(target, "/.")
			case strings.has_prefix(target, "identity:"):
				target = strings.trim_prefix(p.identity, "app/")
			case strings.has_prefix(target, "client:"):
				target = strings.concatenate({"platform/client/", p.client}, context.temp_allocator)
			case strings.has_prefix(target, "theme:"):
				target = strings.concatenate({"platform/theme/", p.theme}, context.temp_allocator)
			}
			if !seen[target] { append(&stack, target) }
		}
	}
	out := make([dynamic]string, context.temp_allocator)
	for k in seen { if k in t.by_path { append(&out, k) } }
	slice.sort(out[:])
	return out[:]
}

// ---- routes --------------------------------------------------------------------------

check_routes :: proc(t: ^Tree) {
	ps := profiles(t)
	for p in ps {
		for h in p.hosts {
			roots := 0
			key_owner := make(map[string]string, context.temp_allocator)
			for m in h.mounts {
				for r in m.rows {
					if r.method == "GET" && r.pattern == "/" {
						roots += 1
						if !r.inline {
							problem("routes", "%s: %s.%s holds a root row; the root is written in the profile's routes.odin", where_(r.pos), m.target, m.table)
						}
						continue
					}
					if lazy_dash(r.pattern) {
						problem("routes", "%s: %s %s has a '-' after a literal, which Lua reads as a lazy quantifier: write %%-", where_(r.pos), r.method, r.pattern)
					}
					if !inside_prefixes(t, r) {
						problem("routes", "%s: %s %s is outside %s's prefixes (/%s, /admin/%s, /api/%s and its README's)",
							where_(r.pos), r.method, r.pattern, r.owner, r.owner, r.owner, r.owner)
					}
					key := key_of(r.pattern)
					if key == "/" { continue }
					if owner, ok := key_owner[key]; ok && owner != r.owner {
						problem("routes", "%s: host %s: the router key %q is claimed by %s and %s", where_(r.pos), h.name, key, owner, r.owner)
					}
					key_owner[key] = r.owner
				}
			}
			if roots != 1 {
				problem("routes", "app/%s/routes.odin: host %s has %d root rows (GET /); a host has exactly one", p.pkg.path, h.name, roots)
			}
		}
	}
	// ROUTES only in web, switched impl and identity packages, and the platform's
	// two tables: platform/web's and platform/hub's (/events).
	for q in t.pkgs {
		switch q.kind {
		case .Web, .Impl, .Identity, .Entry:
			continue
		case .Platform:
			if q.path == "platform/web" || q.path == "platform/hub" { continue }
		case .Other, .Models, .Domain, .Views, .Storetest, .Store, .Family_Root:
		}
		if vd, has := decl(q, "ROUTES"); has {
			problem("routes", "%s: %s declares ROUTES; only web, switched impl and identity packages (and platform/web and platform/hub) do", where_(vd.pos), q.path)
		}
	}
}

// Whether a row sits inside its owner's prefixes: /f, /admin/f, /api/f, or one
// its README lists (a prefix, or a whole pattern).
@(private = "file")
inside_prefixes :: proc(t: ^Tree, r: Row) -> bool {
	lit := literal_start(r.pattern)
	under :: proc(lit, prefix: string) -> bool {
		return lit == prefix || strings.has_prefix(lit, strings.concatenate({strings.trim_suffix(prefix, "/"), "/"}, context.temp_allocator))
	}
	for base in ([]string{"/", "/admin/", "/api/"}) {
		if under(lit, strings.concatenate({base, r.owner}, context.temp_allocator)) { return true }
	}
	for x in readme_prefixes(t, r.owner) {
		if x == r.pattern || under(lit, x) { return true }
	}
	return false
}

// Whether a pattern has a bare '-' after a literal character: in a Lua pattern
// that is a lazy quantifier on it, so "/csp-report" matches "/cspreport" and
// never itself. A '-' after '.', a %-class, a [set] or a %-escape is meant (or
// written %-), and one inside a set is a range.
lazy_dash :: proc(pattern: string) -> bool {
	literal := false // the previous item is one plain character
	for i := 0; i < len(pattern); i += 1 {
		switch c := pattern[i]; c {
		case '%':
			i += 1
			literal = false
		case '[':
			for i += 1; i < len(pattern) && pattern[i] != ']'; i += 1 {
				if pattern[i] == '%' { i += 1 }
			}
			literal = false
		case '-':
			if literal { return true }
			literal = false
		case '.', '(', ')', '^', '$', '*', '+', '?':
			literal = false
		case:
			literal = true
		}
	}
	return false
}

// A pattern's literal start, its %-escapes undone: "/favicon%.ico" → "/favicon.ico".
literal_start :: proc(pattern: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(pattern); i += 1 {
		c := pattern[i]
		if c == '%' && i + 1 < len(pattern) && !is_alnum(pattern[i + 1]) {
			strings.write_byte(&b, pattern[i + 1])
			i += 1
			continue
		}
		if strings.index_byte(MAGIC, c) >= 0 { break }
		strings.write_byte(&b, c)
	}
	return strings.to_string(b)
}

// platform/web's key_of, which the router keys rows by: the first one or two
// whole literal segments, or "/".
MAGIC :: "^$()%.[]*+-?"

key_of :: proc(pattern: string) -> string {
	lit := strings.builder_make(context.temp_allocator)
	all_literal := true
	for i := 0; i < len(pattern); i += 1 {
		c := pattern[i]
		if c == '%' && i + 1 < len(pattern) && !is_alnum(pattern[i + 1]) {
			strings.write_byte(&lit, pattern[i + 1])
			i += 1
			continue
		}
		if strings.index_byte(MAGIC, c) >= 0 {
			all_literal = false
			break
		}
		strings.write_byte(&lit, c)
	}
	l := strings.to_string(lit)
	if l == "/" && all_literal { return "/" }
	segs, end := 0, 0
	for i := 1; i <= len(l) && segs < 2; i += 1 {
		if i == len(l) {
			if all_literal { segs += 1; end = i }
			break
		}
		if l[i] == '/' {
			segs += 1
			end = i
		}
	}
	return l[:end] if end > 0 else "/"
}

is_alnum :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// The prefixes a feature's README lists beyond its own, from the table under
// its `## Prefixes` heading: `| `/data` | why |`. A row with no reason is a
// problem, as D9 asks for one. The platform's is app/platform/web/README.md.
readme_cache: map[string][]string

readme_prefixes :: proc(t: ^Tree, feature: string) -> []string {
	if got, ok := readme_cache[feature]; ok { return got }
	dir := "platform/web" if feature == "platform" else strings.concatenate({"features/", feature})
	path := strings.concatenate({t.root, "/app/", dir, "/README.md"})
	out := make([dynamic]string)
	if data, err := os.read_entire_file(path, context.allocator); err == nil {
		text := string(data)
		in_table := false
		for line in strings.split_lines_iterator(&text) {
			if strings.has_prefix(line, "## ") {
				in_table = strings.trim_space(line) == "## Prefixes"
				continue
			}
			if !in_table || !strings.has_prefix(line, "| `") { continue }
			cells := strings.split(strings.trim(line, "| "), "|", context.temp_allocator)
			prefix := strings.trim(strings.trim_space(cells[0]), "`")
			if len(cells) < 2 || strings.trim_space(cells[1]) == "" {
				problem("routes", "app/%s/README.md: the prefix %s has no reason", dir, prefix)
			}
			append(&out, prefix)
		}
	}
	readme_cache[feature] = out[:]
	return out[:]
}
