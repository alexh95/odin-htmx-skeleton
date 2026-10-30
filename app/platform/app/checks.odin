package app

// ---- the boot checks (§6.1) and the platform's CLI (§8.6) -------------------------------
//
// Each check is fatal with a message; boot prints them all and exits 2. The
// profile's routes_test.odin runs the same checks under `CMD=test build.sh <p>`.
// What the binary can't tell (which feature owns a row's prefix, an unmounted
// table) is tools/check's.

import "core:encoding/json"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import "core:time"

import "../env"
import "../html"
import "../obs"
import "../web"
import "../workers"
import identity "identity:."
import stores "store:."

// The problems in a profile's tables, one line each; empty when it may boot.
boot_checks :: proc(hosts: []Host, sites: []web.Site, jobs: [][]workers.Job, bundle_exts: web.Exts, page_bundles: bit_set[web.Bundle]) -> [dynamic]string {
	problems := make([dynamic]string)
	p :: proc(problems: ^[dynamic]string, format: string, args: ..any) {
		append(problems, fmt.aprintf(format, ..args))
	}
	for h, hi in hosts {
		site := &sites[hi]
		ids := make(map[string]string, context.temp_allocator) // route id → feature
		key_owner := make(map[string]string, context.temp_allocator) // router key → feature
		roots := 0
		for m in h.routes {
			for r in m.rows {
				id := web.route_id(r, context.temp_allocator)
				// 1. a duplicate route id on one host, or a row with no handler
				if prev, dup := ids[id]; dup { p(&problems, "host %s: route %q is mounted twice (%s, %s)", h.name, id, prev, m.feature) }
				ids[id] = m.feature
				if r.handler == nil { p(&problems, "host %s: route %q has no handler", h.name, id) }
				// 2. a row whose prefix or flags need a perm but that declares .Public
				needs := strings.has_prefix(r.pattern, "/admin") || .Step_Up in r.flags || .Lan_Only in r.flags
				if needs && r.perm == .Public { p(&problems, "host %s: route %q needs a perm (/admin, .Step_Up or .Lan_Only) but is .Public", h.name, id) }
				// 3. the root row
				if r.method == .Get && r.pattern == "/" { roots += 1 }
				// 4. the lab rules: no .Lab_Host row where a cookie-setting identity runs; a host
				// with no identity holds only .Public rows
				if .Lab_Host in r.flags && h.identity && identity.SETS_COOKIE { p(&problems, "host %s: .Lab_Host route %q on a host where %s sets a cookie", h.name, id, identity.NAME) }
				if !h.identity && r.perm != .Public { p(&problems, "host %s: route %q needs %v, but no identity runs on this host", h.name, id, r.perm) }
				if .Trusted_Types in r.flags && .Nonce_Csp not_in r.flags { p(&problems, "host %s: route %q has .Trusted_Types without .Nonce_Csp, whose hx-csp makes the htmx policy", h.name, id) }
				// 5. a router key fed by two mounted tables (the "/" bucket is shared by design)
				key := web.key_of(r.pattern, context.temp_allocator)
				if key != "/" {
					if owner, ok := key_owner[key]; ok && owner != m.feature { p(&problems, "host %s: the router key %q is claimed by %s and %s", h.name, key, owner, m.feature) }
					key_owner[key] = m.feature
				}
			}
		}
		if roots != 1 { p(&problems, "host %s: %d root rows (GET /); a host has exactly one", h.name, roots) }
		// 7. a nav href with no GET route on its host
		for item in h.nav {
			found := false
			for m in site.router.rows {
				if m.method == .Get && m.pattern == item.href { found = true; break }
			}
			if !found { p(&problems, "host %s: the nav links %q, which no GET route serves", h.name, item.href) }
		}
	}
	// 6. the embedded bundle carries the extensions main names
	if !web.assets_bundle_present() {
		p(&problems, "no bundle is embedded: run prepare (app/prepare.sh or prepare.bat), which builds app/build/%s/", st.profile)
	} else if have, ok := web.bundle_exts(); !ok || have != bundle_exts {
		p(&problems, "the embedded bundle's extensions differ from main's BUNDLE_EXTS: run prepare")
	}
	if b, ok := web.page_bundles_ok(); !ok {
		p(&problems, "the embedded %v bundle doesn't carry its fixed extensions: run prepare", b)
	}
	for b in page_bundles {
		if !web.page_bundle_embedded(b) { p(&problems, "main's pages load the %v bundle, which isn't embedded: run prepare", b) }
	}
	// 8. a job id mounted twice
	seen := make(map[string]bool, context.temp_allocator)
	for t in jobs {
		for j in t {
			if seen[j.id] { p(&problems, "job %q is mounted twice", j.id) }
			seen[j.id] = true
		}
	}
	return problems
}

// --routes, --features and --limits, with --json; answered once every init has
// recorded its rows, then exit 0.
@(private)
answer_cli :: proc(hosts: []Host) {
	routes, features, limits, as_json := false, false, false, false
	for a in os.args[1:] {
		switch a {
		case "--routes":   routes = true
		case "--features": features = true
		case "--limits":   limits = true
		case "--json":     as_json = true
		}
	}
	if !routes && !features && !limits { return }
	b := strings.builder_make()
	switch {
	case routes:   print_routes(&b, hosts, as_json)
	case features: print_features(&b, hosts, as_json)
	case limits:   print_limits(&b, as_json)
	}
	fmt.print(strings.to_string(b))
	os.exit(0)
}

@(private)
Route_Out :: struct {
	host, feature, id, method, pattern, perm: string,
	flags:                                    []string,
}

@(private)
print_routes :: proc(b: ^strings.Builder, hosts: []Host, as_json: bool) {
	out := make([dynamic]Route_Out)
	for h in hosts {
		for m in h.routes {
			for r in m.rows {
				flags := make([dynamic]string)
				for f in r.flags { append(&flags, fmt.aprint(f)) }
				append(&out, Route_Out{h.name, m.feature, web.route_id(r), fmt.aprint(r.method), r.pattern, fmt.aprint(r.perm), flags[:]})
			}
		}
	}
	if as_json {
		data, _ := json.marshal(out[:], {pretty = true})
		strings.write_string(b, string(data))
		strings.write_byte(b, '\n')
		return
	}
	for r in out {
		fmt.sbprintfln(b, "%-6s %-10s %-34s %-12s %v", r.host, r.feature, r.id, r.perm, r.flags)
	}
}

// The build as /admin/modules shows it (web.build): set once, at app.check.
@(private)
record_build :: proc(hosts: []Host, exts: web.Exts) {
	names := make([dynamic]string)
	routes := make([dynamic]web.Route_Info)
	for h in hosts {
		for m in h.routes {
			seen := false
			for n in names { seen ||= n == m.feature }
			if !seen { append(&names, m.feature) }
			for r in m.rows {
				append(&routes, web.Route_Info{h.name, m.feature, web.route_id(r), fmt.aprint(r.perm), r.flags})
			}
		}
	}
	web.build = {st.profile, stores.NAME, identity.NAME, html.CLIENT, html.THEME, names[:], exts, routes[:]}
}

@(private)
print_features :: proc(b: ^strings.Builder, hosts: []Host, as_json: bool) {
	Features :: struct {
		profile, store, identity, client, theme: string,
		features:                         []string,
	}
	names := make([dynamic]string)
	for h in hosts {
		outer: for m in h.routes {
			for n in names { if n == m.feature { continue outer } }
			append(&names, m.feature)
		}
	}
	if as_json {
		data, _ := json.marshal(Features{st.profile, stores.NAME, identity.NAME, html.CLIENT, html.THEME, names[:]}, {pretty = true})
		strings.write_string(b, string(data))
		strings.write_byte(b, '\n')
		return
	}
	fmt.sbprintfln(b, "profile %s: store %s, identity %s, client %s, theme %s", st.profile, stores.NAME, identity.NAME, html.CLIENT, html.THEME)
	for n in names { fmt.sbprintfln(b, "  %s", n) }
}

@(private)
print_limits :: proc(b: ^strings.Builder, as_json: bool) {
	Env_Out :: struct {
		name, kind, value, def, doc: string,
		set:                         bool,
	}
	envs := make([dynamic]Env_Out)
	for v in env.values() {
		value := "…" if v.row.kind == .Secret && v.text != "" else v.text
		append(&envs, Env_Out{v.row.name, fmt.aprint(v.row.kind), value, v.row.def, v.row.doc, v.set})
	}
	if as_json {
		Out :: struct {
			env:    []Env_Out,
			limits: []obs.Limit,
		}
		data, _ := json.marshal(Out{envs[:], obs.declared_limits()}, {pretty = true})
		strings.write_string(b, string(data))
		strings.write_byte(b, '\n')
		return
	}
	for e in envs { fmt.sbprintfln(b, "%-22s %-9s %-20s %s", e.name, e.kind, e.value, e.doc) }
	strings.write_byte(b, '\n')
	for l in obs.declared_limits() { fmt.sbprintfln(b, "%-10s %-22s %d %s", l.module, l.name, l.value, l.unit) }
}

// --healthcheck: GET /livez on PORT (127.0.0.1), for an image with no shell or
// curl (distroless). Exit 0 on a 200.
@(private)
healthcheck :: proc() -> int {
	port := 8080
	if v := os.get_env("PORT", context.temp_allocator); v != "" {
		if n, ok := parse_port(v); ok { port = n }
	}
	sock, err := net.dial_tcp(net.Endpoint{net.IP4_Loopback, port})
	if err != nil { return 1 }
	defer net.close(sock)
	net.set_option(sock, .Receive_Timeout, 2 * time.Second)
	_, serr := net.send_tcp(sock, transmute([]byte)string("GET /livez HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"))
	if serr != nil { return 1 }
	buf: [64]byte
	n, rerr := net.recv_tcp(sock, buf[:])
	if rerr != nil || n < 12 { return 1 }
	return 0 if string(buf[9:12]) == "200" else 1
}

@(private)
parse_port :: proc(s: string) -> (int, bool) {
	n := 0
	for c in transmute([]byte)s {
		if c < '0' || c > '9' { return 0, false }
		n = n * 10 + int(c - '0')
		if n > 65535 { return 0, false }
	}
	return n, s != ""
}
