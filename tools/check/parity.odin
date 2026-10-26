package main

// ---- parity: every route reached by both suites (PLAN §19.1.11) --------------------------
//
// Per profile: the routes its binary mounts (`bin --routes --json`), the
// request counters each suite's servers left in app/build/coverage/<suite>/<p>/
// (e2e's stopServer and load-tests/run.sh scrape /metrics as a server stops),
// and the `route` lines of tests/parity-waivers.txt. Every route needs a
// non-zero count from both suites, or a waiver with a reason. A waiver no
// profile needs any more is a problem too, so the file stays the list of what
// is actually missing.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"

SUITES :: [2]string{"e2e", "load"}

Waiver :: struct {
	route:  string,
	suites: []string,
	used:   bool,
}

check_parity :: proc(t: ^Tree) {
	waivers := read_waivers(t)
	for p in profiles(t) {
		routes, ok := built_routes(t, p.name)
		if !ok { continue }
		for suite in SUITES {
			counts, ran := suite_counts(t, suite, p.name)
			if !ran {
				problem("parity", "no %s run of %s: app/build/coverage/%s/%s/ holds no counters (run the suite first)", suite, p.name, suite, p.name)
				continue
			}
			for id in routes {
				if counts[id] > 0 { continue }
				waived := false
				for &w in waivers {
					if w.route == id && slice.contains(w.suites, suite) { w.used, waived = true, true }
				}
				if !waived { problem("parity", "%s: the %s suite never reaches %s", p.name, suite, id) }
			}
		}
	}
	for w in waivers {
		if !w.used {
			problem("parity", "tests/parity-waivers.txt: the waiver for %s (%s) is stale: every run reaches it, or no profile mounts it", w.route, strings.join(w.suites, " ", context.temp_allocator))
		}
	}
}

// `route | <route id> | <suites> | <reason>`; perf lines are lib/parity.mjs's.
@(private = "file")
read_waivers :: proc(t: ^Tree) -> [dynamic]Waiver {
	out := make([dynamic]Waiver)
	data, err := os.read_entire_file(strings.concatenate({t.root, "/tests/parity-waivers.txt"}), context.allocator)
	if err != nil { return out }
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		f := strings.split(line, " | ")
		if strings.trim_space(f[0]) != "route" { continue }
		if len(f) < 4 || strings.trim_space(f[3]) == "" {
			problem("parity", "tests/parity-waivers.txt: a route waiver without a reason: %s", line)
			continue
		}
		append(&out, Waiver{route = strings.trim_space(f[1]), suites = strings.fields(f[2])})
	}
	return out
}

// The route ids the profile's built binary mounts, on every host.
@(private = "file")
built_routes :: proc(t: ^Tree, profile: string) -> ([]string, bool) {
	bin := strings.concatenate({t.root, "/app/bin/", profile, ".exe" when ODIN_OS == .Windows else ""})
	if !os.exists(bin) {
		problem("parity", "app/bin/%s isn't built: build it (./build.sh %s) and run both suites first", profile, profile)
		return nil, false
	}
	state, stdout, stderr, err := os.process_exec({command = {bin, "--routes", "--json"}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		problem("parity", "%s --routes --json failed (exit %d, %v): %s", bin, state.exit_code, err, string(stderr))
		return nil, false
	}
	Route_Out :: struct {
		host, id: string,
	}
	rows: []Route_Out
	if jerr := json.unmarshal(stdout, &rows); jerr != nil {
		problem("parity", "%s --routes --json: %v", bin, jerr)
		return nil, false
	}
	out := make([dynamic]string)
	for r in rows {
		if !slice.contains(out[:], r.id) { append(&out, r.id) }
	}
	return out[:], true
}

// The suite's request counts per route id, summed over every server it started.
@(private = "file")
suite_counts :: proc(t: ^Tree, suite, profile: string) -> (map[string]int, bool) {
	counts := make(map[string]int)
	dir := fmt.tprintf("%s/app/build/coverage/%s/%s", t.root, suite, profile)
	entries, err := os.read_all_directory_by_path(dir, context.allocator)
	if err != nil { return counts, false }
	files := 0
	for e in entries {
		if !strings.has_suffix(e.name, ".prom") { continue }
		files += 1
		data, rerr := os.read_entire_file(e.fullpath, context.allocator)
		if rerr != nil { continue }
		text := string(data)
		// app_http_requests_total{route="GET /data"} 44
		for line in strings.split_lines_iterator(&text) {
			start := strings.index(line, `route="`)
			end := strings.index(line, `"} `)
			if start < 0 || end < start { continue }
			n, _ := strconv.parse_int(strings.trim_space(line[end + 3:]), 10)
			counts[line[start + len(`route="`):end]] += n
		}
	}
	return counts, files > 0
}
