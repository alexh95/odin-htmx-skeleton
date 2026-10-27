package main

// ---- the tree: the app's packages, parsed ------------------------------------------------
//
// What compose mode reads before it plans anything: every package under app/, parsed with
// core:odin/parser, and the text of each profile file, so a profile line is taken from the
// source as written (its alignment and its comment) rather than printed back from the AST.
// tools/check reads the same tree the same way to hold the profiles to their rules.

import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:slice"
import "core:strings"

Pkg :: struct {
	path:    string, // app-relative, "/"-separated: "features/notes/web"
	name:    string, // the Odin package name
	feature: string, // f, for app/features/f/… and app/stores/<family>/f
	family:  string, // a store's family
	imports: [dynamic]Import,
	ast:     ^ast.Package,
	lines:   int, // non-blank lines of Odin, tests included
}

Import :: struct {
	alias:  string, // as written; "" when the package name is used
	raw:    string, // "../../platform/web", "store:notes"
	target: string, // app-relative, a collection as written, or "core"
}

Tree :: struct {
	root:    string,
	pkgs:    [dynamic]^Pkg,
	by_path: map[string]^Pkg,
}

@(private = "file")
SKIP_DIRS := [?]string{"vendor", "bin", "build", "static", "migrations", "testdata", "node_modules"}

load_tree :: proc(root: string) -> Tree {
	t := Tree{root = root}
	walk(&t, join(root, "app"), "")
	for p in t.pkgs { t.by_path[p.path] = p }
	return t
}

@(private = "file")
walk :: proc(t: ^Tree, dir, rel: string) {
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil { return }
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool { return a.name < b.name })
	has_odin := false
	for e in entries {
		if e.type == .Directory {
			if slice.contains(SKIP_DIRS[:], e.name) { continue }
			walk(t, join(dir, e.name), e.name if rel == "" else join(rel, e.name))
		} else if strings.has_suffix(e.name, ".odin") {
			has_odin = true
		}
	}
	if !has_odin || rel == "" { return }
	pkg, ok := parser.parse_package_from_path(dir)
	if !ok {
		problem("app/%s doesn't parse", rel)
		return
	}
	p := new(Pkg)
	p.path, p.ast = rel, pkg
	parts := strings.split(rel, "/")
	switch {
	case parts[0] == "features":
		p.feature = parts[1]
	case parts[0] == "stores" && len(parts) == 3:
		p.family, p.feature = parts[1], parts[2]
	}
	for _, f in pkg.files {
		p.name = f.pkg_name
		for imp in f.imports {
			raw := strings.trim(imp.relpath.text, "\"`")
			append(&p.imports, Import{imp.name.text, raw, resolve(rel, raw)})
		}
		s := f.src
		for line in strings.split_lines_iterator(&s) {
			if strings.trim_space(line) != "" { p.lines += 1 }
		}
	}
	append(&t.pkgs, p)
}

// An import as the tree sees it: core and base are "core", a collection stays as written, and a
// relative path becomes app-relative.
resolve :: proc(from, raw: string) -> string {
	if i := strings.index_byte(raw, ':'); i >= 0 {
		switch raw[:i] {
		case "core", "base": return "core"
		}
		return raw
	}
	out := make([dynamic]string, context.temp_allocator)
	for s in strings.split(join(from, raw), "/", context.temp_allocator) {
		switch s {
		case "", ".":
		case "..": if len(out) > 0 { pop(&out) }
		case:      append(&out, s)
		}
	}
	return strings.join(out[:], "/")
}

join :: proc(a, b: string) -> string {
	return strings.concatenate({a, "/", b})
}

// The feature an import names: features/f/… and store:f are f's; anything else is "".
feature_of_target :: proc(target: string) -> string {
	if strings.has_prefix(target, "store:") { return target[len("store:"):] }
	if strings.has_prefix(target, "features/") {
		rest := target[len("features/"):]
		if i := strings.index_byte(rest, '/'); i >= 0 { return rest[:i] }
		return rest
	}
	return ""
}

// ---- AST helpers -------------------------------------------------------------------------

// A package-level `name :: value` or `name := value`, in any file.
decl :: proc(p: ^Pkg, name: string) -> (^ast.Value_Decl, bool) {
	if p == nil { return nil, false }
	for _, f in p.ast.files {
		for d in f.decls {
			vd, ok := d.derived_stmt.(^ast.Value_Decl)
			if !ok { continue }
			for n in vd.names {
				if ident(n) == name { return vd, true }
			}
		}
	}
	return nil, false
}

declares_proc :: proc(p: ^Pkg, name: string) -> bool {
	vd, ok := decl(p, name)
	if !ok || len(vd.values) == 0 { return false }
	_, is := vd.values[0].derived_expr.(^ast.Proc_Lit)
	return is
}

ident :: proc(e: ^ast.Expr) -> string {
	if e == nil { return "" }
	if id, ok := e.derived_expr.(^ast.Ident); ok { return id.name }
	return ""
}

// `pkg.name` → ("pkg", "name").
selector :: proc(e: ^ast.Expr) -> (string, string) {
	if e == nil { return "", "" }
	if s, ok := e.derived_expr.(^ast.Selector_Expr); ok { return ident(s.expr), s.field.name }
	return "", ""
}

string_lit :: proc(e: ^ast.Expr) -> (string, bool) {
	if e == nil { return "", false }
	b, ok := e.derived_expr.(^ast.Basic_Lit)
	if !ok || b.tok.kind != .String { return "", false }
	return strings.trim(b.tok.text, "\"`"), true
}

// `X[:]` → X.
sliced :: proc(e: ^ast.Expr) -> ^ast.Expr {
	if e == nil { return nil }
	if s, ok := e.derived_expr.(^ast.Slice_Expr); ok { return s.expr }
	return nil
}

comp_lit :: proc(e: ^ast.Expr) -> (^ast.Comp_Lit, bool) {
	if e == nil { return nil, false }
	return e.derived_expr.(^ast.Comp_Lit)
}

// The element type of `[?]T{…}`: "app.Mount"; of `[?][]T{…}`: "[]hub.Topic".
comp_elem_type :: proc(c: ^ast.Comp_Lit) -> string {
	if c.type == nil { return "" }
	at, ok := c.type.derived_expr.(^ast.Array_Type)
	if !ok { return "" }
	if inner, is := at.elem.derived_expr.(^ast.Array_Type); is {
		a, b := selector(inner.elem)
		return strings.concatenate({"[]", a, ".", b})
	}
	a, b := selector(at.elem)
	return strings.concatenate({a, ".", b})
}

// The package an alias names in a package's files: its import's target.
alias_target :: proc(t: ^Tree, p: ^Pkg, alias: string) -> string {
	for imp in p.imports {
		name := imp.alias
		if name == "" {
			if q, ok := t.by_path[imp.target]; ok { name = q.name }
		}
		if name == alias { return imp.target }
	}
	return ""
}

// Every package alias a node mentions (`notes_web.ROUTES` → "notes_web").
@(private = "file") aliases_seen: ^[dynamic]string

aliases_in :: proc(n: ^ast.Node) -> []string {
	out := make([dynamic]string)
	aliases_seen = &out
	ast.inspect(n, proc(n: ^ast.Node) -> bool {
		if n == nil { return true }
		if s, ok := n.derived.(^ast.Selector_Expr); ok {
			if a := ident(s.expr); a != "" && !slice.contains(aliases_seen[:], a) { append(aliases_seen, a) }
		}
		return true
	})
	return out[:]
}
