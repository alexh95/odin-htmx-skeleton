package landing

// ---- landing: the starter's catalog, and the init command a selection makes (PLAN §15.5) ----
//
// The catalog is docs/catalog.json, `odin run tools/init -- --list --json`, which CI's generator
// job holds current: embedded at build time, read once at boot. `plan` mirrors the generator's
// own rules closely enough to show what a selection pulls in and why it would be refused; the
// generator's `--explain` stays the authority, and the page says so.

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

CATALOG_JSON :: #load("../../../docs/catalog.json", string)

Feature :: struct {
	name:     string,
	lines:    int,
	stores:   []string, // the store families it has stores in; none: it keeps nothing
	sqlite:   string,   // "none", "any", "required" or "never"
	deps:     []string,
	switched: []string, // its implementations behind one switch
	declares: []string,
	profiles: []string,
}

Profile :: struct {
	name, store, identity, client, theme: string,
	features:                             []string,
}

Families :: struct {
	store, identity, client, theme: []string,
}

Catalog :: struct {
	features: []Feature,
	families: Families,
	profiles: []Profile,
}

catalog: Catalog

// The catalog, parsed into context.allocator for the process; false when the embedded file
// doesn't read, which boot treats as fatal.
init :: proc() -> bool {
	return json.unmarshal_string(CATALOG_JSON, &catalog, spec = .JSON) == nil && len(catalog.features) > 0
}

feature :: proc(name: string) -> ^Feature {
	for &f in catalog.features { if f.name == name { return &f } }
	return nil
}

// ---- a selection, and what it makes -------------------------------------------------------

MAX_NAME :: 40

Choice :: struct {
	name:     string,
	features: []string,
	store, identity, client, theme: string, // "" leaves the generator's default
}

Plan :: struct {
	features: []string, // the selection closed over its dependencies, asked first
	added:    []string, // what the closure pulled in
	root:     string,   // the page at `/`
	store:    string,   // the store family the build gets
	lines:    int,      // the features' size, roughly
	problems: []string, // why the generator would refuse it
	command:  string,
}

// The generator's roots, in its order (tools/init's ROOTS): the first selected is `/`, else
// home joins.
ROOTS :: [?]string{"dashboard", "landing", "home"}

plan :: proc(c: Choice) -> Plan {
	p: Plan
	features := make([dynamic]string, context.temp_allocator)
	added := make([dynamic]string, context.temp_allocator)
	problems := make([dynamic]string, context.temp_allocator)

	close :: proc(name: string, features, added: ^[dynamic]string, asked: bool) {
		if slice.contains(features[:], name) { return }
		f := feature(name)
		if f == nil { return }
		append(features, name)
		if !asked { append(added, name) }
		for d in f.deps { close(d, features, added, false) }
	}
	for name in c.features {
		if feature(name) == nil {
			append(&problems, fmt.tprintf("no feature %q", name))
			continue
		}
		close(name, &features, &added, true)
	}
	for r in ROOTS {
		if slice.contains(features[:], r) { p.root = r; break }
	}
	if p.root == "" {
		p.root = "home"
		close("home", &features, &added, false)
	}

	// The store: the one asked for, else SQLite when a feature needs it, else memory.
	p.store = c.store
	if p.store == "" {
		p.store = "memory"
		for name in features {
			if f := feature(name); f != nil && f.sqlite == "required" { p.store = "sqlite" }
		}
	}
	for name in features {
		f := feature(name)
		p.lines += f.lines
		switch {
		case f.sqlite == "required" && p.store != "sqlite": append(&problems, fmt.tprintf("%s has no %s store: use --store sqlite", name, p.store))
		case f.sqlite == "never" && p.store != "memory":    append(&problems, fmt.tprintf("%s has no %s store: use --store memory", name, p.store))
		}
	}
	if !valid_name(c.name) {
		append(&problems, fmt.tprintf("the name is lower-case letters, digits and dashes, starting with a letter, at most %d", MAX_NAME))
	}
	if len(c.features) == 0 { append(&problems, "pick at least one feature") }

	b := strings.builder_make(context.temp_allocator)
	// A refused name is never echoed into the command offered for copying (M3-05).
	fmt.sbprintf(&b, "odin run tools/init -- %s", c.name if valid_name(c.name) else "<name>")
	if len(c.features) > 0 { fmt.sbprintf(&b, " --features %s", strings.join(c.features, ",", context.temp_allocator)) }
	flags := [?][2]string{{"--store", c.store}, {"--identity", c.identity}, {"--client", c.client}, {"--theme", c.theme}}
	for f in flags {
		if f[1] != "" { fmt.sbprintf(&b, " %s %s", f[0], f[1]) }
	}
	p.features, p.added, p.problems, p.command = features[:], added[:], problems[:], strings.to_string(b)
	return p
}

valid_name :: proc(s: string) -> bool {
	if len(s) == 0 || len(s) > MAX_NAME || s[0] < 'a' || s[0] > 'z' { return false }
	for c in transmute([]byte)s {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') { return false }
	}
	return true
}

// A family member the catalog names, or "": what a request asked for is only ever one of these.
member :: proc(names: []string, asked: string) -> string {
	for n in names { if n == asked { return n } }
	return ""
}
