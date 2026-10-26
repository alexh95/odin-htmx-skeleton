package main

// ---- bundle: a profile's page bundles, derived from the build -----------
//
//   odin run tools/bundle -- <profile> [--repo DIR] [--htmx DIR] [--out DIR] [--list]
//
// prepare runs it before the build that #loads its output (D19, PLAN §12.1):
//
//   1. Ask the compiler which files the profile's build reaches:
//      build.{sh,bat} <profile> -export-dependencies:json. The build line
//      resolves the four collections, so the list names exactly the selected
//      family members, and a package no import reaches is not in it.
//   2. Union the one-line `EXTS ::` of every reached package, web and switched
//      implementation alike, and the `BUNDLES ::` lines of the packages whose
//      pages load a fixed page bundle (scripting, compat).
//   3. Write each bundle: htmx.min.js, then the extensions in load order (hx-csp
//      first), joined by "\n;\n" under a `/* exts: … */` header. An empty union
//      is htmx.min.js byte for byte, with no header: `minimal` and `skeleton`
//      keep the skeleton's file and its crc32 name.
//   4. Precompress each with `brotli -q 11` and `gzip -9 -n` (see compress).
//   5. Write the profile's app.css (the theme's sheet, then each reached
//      feature's static CSS) and its client's app.js, precompressed the same way.
//
// The ext tables come from the app's own leaf package, imported here, so the
// header this writes and the boot check that reads it can't disagree on a
// name. Spike S0.10's fixture (tools/bundle/fixture, run with --repo)
// re-exports the same package.
//
// An `EXTS` line may name another package's EXTS (chat_web unions its
// transports'). Those references need no following: a package can only name a
// constant of a package it imports, so the compiler reached that package too,
// and its own line is in the scan.

import chash "core:crypto/hash"
import "core:encoding/hex"
import "core:encoding/json"
import "core:fmt"
import "core:hash"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import ext "../../app/platform/ext"

Options :: struct {
	profile: string,
	repo:    string, // holds build.{sh,bat} and app/
	htmx:    string, // the pinned tarball's dist/: htmx.min.js and ext/*.min.js
	out:     string, // bundles land in <out>/<profile>/
	list:    bool,
}

Decl :: struct {
	pkg:     string, // directory under app/
	exts:    ext.Exts,
	bundles: bit_set[ext.Bundle],
}

main :: proc() {
	opt := parse_args(os.args[1:])
	// Absolute, because build.{sh,bat} cd to the repo root before the scan build writes there.
	_ = os.make_directory_all(opt.out)
	opt.repo, opt.htmx, opt.out = abs(opt.repo), abs(opt.htmx), abs(opt.out)
	dir := path_join(opt.out, opt.profile)
	if err := os.make_directory_all(dir); err != nil && !os.is_dir(dir) {
		fatal(fmt.tprintf("can't create %s: %v", dir, err))
	}

	files := reached_files(opt, dir)
	decls := scan(opt, files)

	main_exts: ext.Exts
	pages: bit_set[ext.Bundle] = {.Main}
	for d in decls {
		main_exts += d.exts
		pages += d.bundles
	}
	if bad := main_exts & ext.LAB_ONLY; bad != {} {
		fatal(fmt.tprintf("%s would reach Main: the lab-only extensions ride only in the fixed page bundles (D21)", ext.list(bad)))
	}

	fmt.printfln("bundle %s: %d app files reached; extensions declared by:%s", opt.profile, len(files), len(decls) == 0 ? " none" : "")
	for d in decls {
		fmt.printf("  %-34s", d.pkg)
		if d.exts != {} {
			fmt.printf(" EXTS %s", ext.list(d.exts, context.temp_allocator))
		}
		if d.bundles != {} {
			fmt.print(" BUNDLES")
			for p in d.bundles {
				fmt.printf(" %v", p)
			}
		}
		fmt.println()
	}

	tools := find_compressors()
	fmt.printfln("%-14s %4s %8s %8s %8s  %-8s  %s", "bundle", "exts", "raw B", "gzip B", "br B", "crc32", "sha256")
	for b in ext.Bundle {
		path := path_join(dir, bundle_file(b))
		if b not_in pages {
			remove_outputs(path) // a bundle this profile no longer loads must not linger
			continue
		}
		set := b == .Main ? main_exts : ext.PAGE_EXTS[b]
		js := compose(opt.htmx, set)
		if err := os.write_entire_file(path, js); err != nil {
			fatal(fmt.tprintf("can't write %s: %v", path, err))
		}
		gz, br := compress(path, tools)
		sum := hex.encode(chash.hash_bytes(.SHA256, js, context.temp_allocator), context.temp_allocator)
		fmt.printfln(
			"%-14v %4s %8s %8s %8s  %08x  %s",
			b, fmt.tprint(card(set)), fmt.tprint(len(js)), size_or_dash(gz), size_or_dash(br), hash.crc32(js), sum,
		)
	}

	// The stylesheet and the client's script, from the same reached files.
	for out in ([]struct{name: string, data: []byte}{{"app.css", stylesheet(opt, files)}, {"app.js", client_js(opt, files)}}) {
		path := path_join(dir, out.name)
		if err := os.write_entire_file(path, out.data); err != nil {
			fatal(fmt.tprintf("can't write %s: %v", path, err))
		}
		gz, br := compress(path, tools)
		fmt.printfln("%-14s %4s %8s %8s %8s  %08x", out.name, "", fmt.tprint(len(out.data)), size_or_dash(gz), size_or_dash(br), hash.crc32(out.data))
	}
}

// ---- 5. the stylesheet and the client's script ----------------------------
//
// One stylesheet per profile: the platform's (app/platform/static/app.css) for the
// build's theme, then each reached feature's static/*.css, in feature order. The
// lite theme is the full sheet with every `/* full-only: … */` … `/* /full-only */`
// region cut out, so the two never drift; the marker lines go in both.

THEME_LITE :: "platform/theme/lite/"

stylesheet :: proc(opt: Options, files: []string) -> []byte {
	lite := false
	for f in files {
		if strings.has_prefix(f, THEME_LITE) { lite = true; break }
	}
	b := strings.builder_make()
	src := string(read(path_join(opt.repo, "app/platform/static/app.css")))
	cutting := false
	for line in strings.split_lines_iterator(&src) {
		t := strings.trim_space(line)
		if strings.has_prefix(t, "/* full-only") {
			cutting = lite
			continue
		}
		if t == "/* /full-only */" {
			cutting = false
			continue
		}
		if cutting { continue }
		strings.write_string(&b, line)
		strings.write_byte(&b, '\n')
	}
	for f in reached_features(files) {
		dir := path_join(opt.repo, "app/features", f, "static")
		entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil { continue }
		names := make([dynamic]string, context.temp_allocator)
		for e in entries {
			if strings.has_suffix(e.name, ".css") { append(&names, e.name) }
		}
		slice.sort(names[:])
		for n in names {
			strings.write_string(&b, "\n")
			strings.write_bytes(&b, read(path_join(dir, n)))
		}
	}
	return b.buf[:]
}

// The build's client member owns app.js (its delegated listener and behaviours).
client_js :: proc(opt: Options, files: []string) -> []byte {
	PREFIX :: "platform/client/"
	for f in files {
		if !strings.has_prefix(f, PREFIX) { continue }
		member := f[len(PREFIX):]
		member = member[:strings.index_byte(member, '/')]
		return read(path_join(opt.repo, "app/platform/client", member, "app.js"))
	}
	fatal("the build reaches no client member (app/platform/client/<member>/): check build.sh's -collection:client")
	return nil
}

// The features the build reaches, from their packages' paths, in name order.
reached_features :: proc(files: []string) -> []string {
	out := make([dynamic]string)
	for f in files {
		if !strings.has_prefix(f, "features/") { continue }
		rest := f[len("features/"):]
		name := rest[:strings.index_byte(rest, '/')]
		if !slice.contains(out[:], name) { append(&out, name) }
	}
	slice.sort(out[:])
	return out[:]
}

// ---- 1. the compiler's file list ----------------------------------------

Deps :: struct {
	source_files: []string,
}

// A scan build is an ordinary build of the profile with the dependency export
// on (`odin check` can't export). It must not need prepare's output (the app
// #loads the bundles under `when #exists`), and a link failure doesn't matter:
// Odin writes the list before it links. `odin build` compiles `_test.odin`
// files too, so a package that only a test imports is in the list; if it
// declares EXTS, boot check 6 refuses the binary, since main's BUNDLE_EXTS
// doesn't name it.
reached_files :: proc(opt: Options, dir: string) -> []string {
	deps := path_join(dir, "deps.json")
	bin := path_join(dir, ODIN_OS == .Windows ? ".scan.exe" : ".scan")
	os.remove(deps)
	cmd: []string
	when ODIN_OS == .Windows {
		// cmd reads a '/' as a switch, so the script's path takes backslashes.
		bat, _ := strings.replace_all(abs(path_join(opt.repo, "build.bat")), "/", `\`)
		cmd = {"cmd.exe", "/c", bat, opt.profile}
	} else {
		cmd = {"sh", path_join(opt.repo, "build.sh"), opt.profile}
	}
	cmd = slice.concatenate([][]string{cmd, {"-export-dependencies:json", strings.concatenate({"-export-dependencies-file:", deps})}})

	env, _ := os.environ(context.allocator)
	env = slice.concatenate([][]string{env, {"CMD=build", strings.concatenate({"OUT=", bin})}})
	state, stdout, stderr, err := os.process_exec({command = cmd, env = env}, context.allocator)
	os.remove(bin)
	os.remove(strings.concatenate({strings.trim_suffix(bin, ".exe"), ".pdb"}))
	data, rerr := os.read_entire_file(deps, context.allocator)
	if err != nil || rerr != nil {
		fmt.eprint(string(stdout), string(stderr))
		fatal(fmt.tprintf("the scan build wrote no %s (exit %d, %v): fix the build first", deps, state.exit_code, err))
	}

	d: Deps
	if jerr := json.unmarshal(data, &d); jerr != nil {
		fatal(fmt.tprintf("can't read %s: %v", deps, jerr))
	}
	app := strings.concatenate({slash(abs(path_join(opt.repo, "app"))), "/"})
	files: [dynamic]string
	for f in d.source_files {
		s := slash(f)
		if has_prefix_fold(s, app) {
			append(&files, s[len(app):])
		}
	}
	if len(files) == 0 {
		fatal(fmt.tprintf("the scan build reached no file under %s", app))
	}
	slice.sort(files[:])
	if opt.list {
		for f in files {
			fmt.printfln("  reached app/%s", f)
		}
	}
	return files[:]
}

// ---- 2. the one-line declarations ---------------------------------------
//
// The lint (tools/check exts) keeps each declaration on one line at column 0,
// so a line scan reads it exactly: `EXTS :: a.EXTS + bit_set[web.Ext]{.Sse, .Ws}`.
// Only the braces' members count; the rest names types or other packages' EXTS.

scan :: proc(opt: Options, files: []string) -> []Decl {
	by_pkg: map[string]Decl
	for f in files {
		data, err := os.read_entire_file(path_join(opt.repo, "app", f), context.allocator)
		if err != nil {
			fatal(fmt.tprintf("can't read app/%s: %v", f, err))
		}
		pkg := f[:max(strings.last_index_byte(f, '/'), 0)]
		text := string(data)
		for line in strings.split_lines_iterator(&text) {
			exts, is_exts := decl_value(line, "EXTS")
			bundles, is_bundles := decl_value(line, "BUNDLES")
			if !is_exts && !is_bundles {
				continue
			}
			d := by_pkg[pkg]
			d.pkg = pkg
			for m in members(exts, f) {
				e, found := reflect.enum_from_name(ext.Ext, m)
				if !found {
					fatal(fmt.tprintf("app/%s: .%s is not an htmx extension", f, m))
				}
				d.exts += {e}
			}
			for m in members(bundles, f) {
				b, found := reflect.enum_from_name(ext.Bundle, m)
				if !found {
					fatal(fmt.tprintf("app/%s: .%s is not a page bundle", f, m))
				}
				d.bundles += {b}
			}
			by_pkg[pkg] = d
		}
	}
	decls: [dynamic]Decl
	for _, d in by_pkg {
		append(&decls, d)
	}
	slice.sort_by(decls[:], proc(a, b: Decl) -> bool {return a.pkg < b.pkg})
	return decls[:]
}

// `NAME :: value` at column 0, without a trailing comment.
decl_value :: proc(line, name: string) -> (value: string, ok: bool) {
	if !strings.has_prefix(line, name) {
		return
	}
	rest := strings.trim_left_space(line[len(name):])
	if !strings.has_prefix(rest, "::") {
		return
	}
	value = rest[2:]
	if i := strings.index(value, "//"); i >= 0 {
		value = value[:i]
	}
	return value, true
}

// The `.Name` members inside every {…} of a declaration's value.
members :: proc(value, file: string) -> []string {
	if strings.contains_any(value, "-&~|") {
		fatal(fmt.tprintf("app/%s: a bundle declaration only unions (+): %s", file, strings.trim_space(value)))
	}
	out: [dynamic]string
	rest := value
	for {
		open := strings.index_byte(rest, '{')
		if open < 0 {
			break
		}
		close := strings.index_byte(rest[open:], '}')
		if close < 0 {
			fatal(fmt.tprintf("app/%s: a bundle declaration must close its braces on its one line", file))
		}
		inner := rest[open + 1:open + close]
		for raw in strings.split_iterator(&inner, ",") {
			m := strings.trim_space(raw)
			if m == "" {
				continue
			}
			if !strings.has_prefix(m, ".") {
				fatal(fmt.tprintf("app/%s: write members as .Name, not %q", file, m))
			}
			append(&out, m[1:])
		}
		rest = rest[open + close + 1:]
	}
	return out[:]
}

// ---- 3. compose ---------------------------------------------------------

compose :: proc(htmx_dir: string, set: ext.Exts) -> []byte {
	core := read(path_join(htmx_dir, "htmx.min.js"))
	if set == {} {
		return core
	}
	b := strings.builder_make()
	strings.write_string(&b, ext.header(set))
	strings.write_bytes(&b, core)
	for e in ext.load_order(set) {
		strings.write_string(&b, "\n;\n")
		strings.write_bytes(&b, read(path_join(htmx_dir, "ext", ext.FILES[e])))
	}
	return b.buf[:]
}

bundle_file :: proc(b: ext.Bundle) -> string {
	return strings.concatenate({strings.to_lower(fmt.tprint(b)), ".js"})
}

// ---- 4. compress --------------------------------------------------------
//
// Odin has no brotli, and gzips only through vendor:zlib, a C library that
// links on Windows only with -linker:msvc (11 §9). So the tool runs the two
// CLIs, which write <file>.br and <file>.gz beside the input, never through a
// pipe (a Windows pipe in text mode would corrupt them):
//   - Linux (CI, the Docker image, a release): both are required. Debian and the
//     GitHub runner images ship them; a bare Ubuntu needs `apt-get install brotli`.
//   - Windows (a dev build): the PATH first, then Git for Windows, which ships
//     both (mingw64/bin/brotli.exe, usr/bin/gzip.exe). Without brotli the build
//     ships gzip and identity; without gzip, identity alone (PLAN §12.1). The
//     binary #loads each encoding under `when #exists` and offers what it has.

Compressors :: struct {
	brotli, gzip: string, // "" when not found
}

find_compressors :: proc() -> Compressors {
	c := Compressors{find_tool("brotli"), find_tool("gzip")}
	for t in ([]struct{name, path: string}{{"brotli", c.brotli}, {"gzip", c.gzip}}) {
		if t.path != "" {
			continue
		}
		when ODIN_OS == .Windows {
			fmt.eprintfln("bundle: warning: no %s found (PATH, Git for Windows): this dev build ships without .%s", t.name, t.name == "gzip" ? "gz" : "br")
		} else {
			fatal(fmt.tprintf("no %s on PATH: a Linux build must ship it (apt-get install -y %s)", t.name, t.name))
		}
	}
	return c
}

find_tool :: proc(name: string) -> string {
	if runs({name, "--version"}) {
		return name
	}
	when ODIN_OS == .Windows {
		// `git --exec-path` is <root>/mingw64/libexec/git-core wherever Git is installed.
		state, stdout, _, err := os.process_exec({command = {"git", "--exec-path"}}, context.temp_allocator)
		if err != nil || state.exit_code != 0 {
			return ""
		}
		root := slash(strings.trim_space(string(stdout)))
		root = strings.trim_suffix(root, "/libexec/git-core")
		root = root[:max(strings.last_index_byte(root, '/'), 0)]
		for sub in ([]string{"mingw64/bin", "usr/bin"}) {
			p := strings.concatenate({root, "/", sub, "/", name, ".exe"})
			if os.exists(p) && runs({p, "--version"}) {
				return p
			}
		}
	}
	return ""
}

compress :: proc(path: string, c: Compressors) -> (gz, br: int) {
	gz, br = -1, -1
	remove_outputs(path, keep_identity = true)
	p := slash(path)
	if c.brotli != "" {
		must_run({c.brotli, "-q", "11", "-f", p})
		br = file_size(strings.concatenate({path, ".br"}))
	}
	if c.gzip != "" {
		must_run({c.gzip, "-9", "-n", "-k", "-f", p})
		gz = file_size(strings.concatenate({path, ".gz"}))
	}
	return
}

remove_outputs :: proc(path: string, keep_identity := false) {
	if !keep_identity {
		os.remove(path)
	}
	os.remove(strings.concatenate({path, ".br"}))
	os.remove(strings.concatenate({path, ".gz"}))
}

// ---- helpers ------------------------------------------------------------

runs :: proc(cmd: []string) -> bool {
	state, _, _, err := os.process_exec({command = cmd}, context.temp_allocator)
	return err == nil && state.exit_code == 0
}

must_run :: proc(cmd: []string) {
	state, stdout, stderr, err := os.process_exec({command = cmd}, context.temp_allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprint(string(stdout), string(stderr))
		fatal(fmt.tprintf("%v failed (exit %d, %v)", cmd, state.exit_code, err))
	}
}

read :: proc(path: string) -> []byte {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fatal(fmt.tprintf("can't read %s: %v (run prepare: it fetches the pinned htmx tarball)", path, err))
	}
	return data
}

file_size :: proc(path: string) -> int {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		fatal(fmt.tprintf("the compressor wrote no %s", path))
	}
	return len(data)
}

size_or_dash :: proc(n: int) -> string {
	return n < 0 ? "-" : fmt.tprint(n)
}

path_join :: proc(parts: ..string) -> string {
	return strings.join(parts, "/")
}

abs :: proc(path: string) -> string {
	a, err := os.get_absolute_path(path, context.allocator)
	if err != nil {
		fatal(fmt.tprintf("can't resolve %s: %v", path, err))
	}
	return a
}

slash :: proc(path: string) -> string {
	s, _ := strings.replace_all(path, `\`, "/")
	return s
}

// Windows paths compare without case: the compiler and the shell may spell the
// drive letter differently.
has_prefix_fold :: proc(s, prefix: string) -> bool {
	when ODIN_OS == .Windows {
		return len(s) >= len(prefix) && strings.equal_fold(s[:len(prefix)], prefix)
	} else {
		return strings.has_prefix(s, prefix)
	}
}

parse_args :: proc(args: []string) -> Options {
	opt := Options {
		repo = ".",
		htmx = "app/vendor/htmx",
		out  = "app/build",
	}
	i := 0
	for i < len(args) {
		a := args[i]
		switch {
		case a == "--repo":
			opt.repo = next_arg(args, &i, a)
		case a == "--htmx":
			opt.htmx = next_arg(args, &i, a)
		case a == "--out":
			opt.out = next_arg(args, &i, a)
		case a == "--list":
			opt.list = true
		case a == "-h", a == "--help":
			usage()
		case strings.has_prefix(a, "-"):
			fatal(fmt.tprintf("unknown flag %q", a))
		case:
			if opt.profile != "" {
				fatal(fmt.tprintf("unexpected extra argument %q", a))
			}
			opt.profile = a
		}
		i += 1
	}
	if opt.profile == "" {
		usage()
	}
	return opt
}

next_arg :: proc(args: []string, i: ^int, flag: string) -> string {
	i^ += 1
	if i^ >= len(args) {
		fatal(fmt.tprintf("%s needs a value", flag))
	}
	return args[i^]
}

usage :: proc() {
	fmt.eprintln("usage: odin run tools/bundle -- <profile> [--repo DIR] [--htmx DIR] [--out DIR] [--list]")
	fmt.eprintln("  <profile>  a profile build.{sh,bat} knows, e.g. full")
	fmt.eprintln("  --repo     the directory holding build.{sh,bat} and app/; default .")
	fmt.eprintln("  --htmx     the pinned htmx 4.0.0 dist/ (htmx.min.js, ext/); default app/vendor/htmx")
	fmt.eprintln("  --out      bundles go to <out>/<profile>/; default app/build")
	fmt.eprintln("  --list     also print every app file the build reaches")
	os.exit(2)
}

fatal :: proc(msg: string) {
	fmt.eprintfln("bundle: %s", msg)
	os.exit(1)
}
