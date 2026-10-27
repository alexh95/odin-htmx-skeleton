package main

// ---- --verify: the plan, applied to a scratch copy, built and checked there first ---------
//
// On by default (PLAN §7.4): the tree is copied to a scratch directory (no .git, no builds, no
// node_modules), the plan is written there, and the copy is prepared, built and tested through
// build.*, held to tools/check's profile, routes, topics and exts, and asked `--features
// --json`, whose features and family members must be the plan's. Only then does init ask to
// touch this checkout. A failure leaves the scratch copy for a look and changes nothing here.

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

// From the root: what's built, fetched or recorded, never source.
@(private = "file")
SKIP_COPY := [?]string{".git", "app/bin", "app/build", "e2e/node_modules", "e2e/test-results", "e2e/playwright-report", "load-tests/results"}

verify :: proc(s: Selection) {
	verify_profile(s.name, s.features, s.members)
}

verify_profile :: proc(name: string, want_features: []string = nil, want_members: [Family]string = {}) {
	scratch := join(slashed(os.temp_directory(context.allocator) or_else "."), fmt.tprintf("odin-init-verify-%d", os.get_pid()))
	_ = os.remove_all(scratch)
	fmt.printfln("verify: a scratch copy at %s ...", scratch)
	if !copy_tree(".", scratch, "") { fatal(fmt.tprintf("verify: couldn't copy the tree to %s", scratch)) }
	commit(root = scratch, quiet = true)

	step :: proc(scratch, what: string, cmd: []string, extra_env: []string = nil) -> string {
		env, _ := os.environ(context.allocator)
		env = slice.concatenate([][]string{env, extra_env})
		state, stdout, stderr, err := os.process_exec({working_dir = scratch, command = cmd, env = env}, context.allocator)
		if err != nil || state.exit_code != 0 {
			fmt.eprint(string(stdout), string(stderr))
			fatal(fmt.tprintf("verify: %s failed (exit %d, %v); nothing changed here. The scratch copy stays at %s", what, state.exit_code, err, scratch))
		}
		fmt.printfln("verify: %s ok", what)
		return string(stdout)
	}
	bin: string
	when ODIN_OS == .Windows {
		bat := strings.concatenate({scratch, `\build.bat`})
		bat, _ = strings.replace_all(bat, "/", `\`)
		prep, _ := strings.replace_all(strings.concatenate({scratch, `\app\prepare.bat`}), "/", `\`)
		step(scratch, "prepare", {"cmd.exe", "/c", prep})
		step(scratch, fmt.tprintf("build.bat %s", name), {"cmd.exe", "/c", bat, name})
		step(scratch, fmt.tprintf("CMD=test build.bat %s", name), {"cmd.exe", "/c", bat, name}, {"CMD=test"})
		bin = fmt.tprintf("%s/app/bin/%s.exe", scratch, name)
	} else {
		step(scratch, "prepare", {"sh", "app/prepare.sh"})
		step(scratch, fmt.tprintf("./build.sh %s", name), {"sh", "build.sh", name})
		step(scratch, fmt.tprintf("CMD=test ./build.sh %s", name), {"sh", "build.sh", name}, {"CMD=test"})
		bin = fmt.tprintf("%s/app/bin/%s", scratch, name)
	}
	// Every gate CI's `check all` runs before both suites: a plan that broke the layering
	// passed here and failed the new project's first CI run (M2-20).
	step(scratch, "tools/check imports profile routes contracts topics exts", {"odin", "run", "tools/check", "--", "imports", "profile", "routes", "contracts", "topics", "exts"})
	out := step(scratch, fmt.tprintf("%s --features --json", name), {bin, "--features", "--json"})

	Features :: struct {
		profile, store, identity, client, theme: string,
		features:                                []string,
	}
	got: Features
	if err := json.unmarshal(transmute([]byte)out, &got); err != nil { fatal(fmt.tprintf("verify: can't read --features --json: %v", err)) }
	if want_features != nil {
		missing := make([dynamic]string, context.temp_allocator)
		for f in want_features {
			if !slice.contains(got.features, f) { append(&missing, f) }
		}
		extra := make([dynamic]string, context.temp_allocator)
		for f in got.features {
			if f != "platform" && !slice.contains(want_features, f) { append(&extra, f) }
		}
		if len(missing) > 0 || len(extra) > 0 {
			fatal(fmt.tprintf("verify: the build mounts %v, the plan %v (missing %v, extra %v); the scratch copy stays at %s", got.features, want_features, missing[:], extra[:], scratch))
		}
	}
	gotm := [Family]string{.Store = got.store, .Identity = got.identity, .Client = got.client, .Theme = got.theme}
	for fam in Family {
		if want_members[fam] != "" && gotm[fam] != want_members[fam] {
			fatal(fmt.tprintf("verify: the build's %s is %s, the plan's %s; the scratch copy stays at %s", FAMILY_FLAGS[fam], gotm[fam], want_members[fam], scratch))
		}
	}
	fmt.println("verify: the build mounts what the plan says")
	_ = os.remove_all(scratch)
}

// The tree, without what's built or fetched: a scratch copy init can write its plan into.
@(private = "file")
copy_tree :: proc(from, to, rel: string) -> bool {
	if os.make_directory_all(to) != nil { return false }
	entries, err := os.read_all_directory_by_path(from, context.temp_allocator)
	if err != nil { return false }
	for e in entries {
		src, dst := join(from, e.name), join(to, e.name)
		if e.type == .Directory {
			sub := e.name if rel == "" else join(rel, e.name)
			if slice.contains(SKIP_COPY[:], sub) || e.name == "node_modules" { continue }
			if !copy_tree(src, dst, sub) { return false }
			continue
		}
		data, rerr := os.read_entire_file(src, context.allocator)
		if rerr != nil { return false }
		if os.write_entire_file(dst, data) != nil { return false }
		delete(data)
	}
	return true
}

slashed :: proc(s: string) -> string {
	r, _ := strings.replace_all(s, `\`, "/")
	return r
}
