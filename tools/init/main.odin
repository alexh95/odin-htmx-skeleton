package main

// ---- init: rename this skeleton for a new project -----------------------
//
// A one-time scaffolding tool. Run it from the repo root after cloning the
// template:
//
//   odin run tools/init -- <new-name> [--wordmark "New·Name"] [--suffix "..."]
//                                     [--repo <url>] [--yes]
//
// <new-name> is the machine name (lower-case letters, digits, dashes; starts
// with a letter), e.g. `acme-crm`. It becomes the binary, the Fly app, the
// Docker image, the apollo-11 service, the startup banner, and the package
// names. --wordmark / --suffix / --repo set the three brand constants the
// layout reads (see app/src/views/brand.odin); sensible defaults are derived
// from <new-name>.
//
// The tool is itself an Odin program — the skeleton's own tooling stays on the
// stack it teaches. It edits a fixed set of files (no directory walk), so what
// it touches is auditable right here.

import "core:fmt"
import "core:os"
import "core:strings"

// A literal find/replace. Applied in order, so list the most specific first.
Repl :: struct {
	old, new: string,
}

Options :: struct {
	name:     string,
	wordmark: string,
	suffix:   string,
	repo:     string,
	yes:      bool,
}

main :: proc() {
	opt := parse_args(os.args[1:])

	fmt.printfln("Rename this skeleton to %q:", opt.name)
	fmt.printfln("  binary / Fly app / image / service : %s", opt.name)
	fmt.printfln("  brand wordmark (topbar)            : %s", opt.wordmark)
	fmt.printfln("  title suffix (<title>)             : %s", opt.suffix)
	fmt.printfln("  GitHub repo (About page)           : %s", opt.repo)
	fmt.println()

	if !opt.yes && !confirm("Proceed? [y/N] ") {
		fmt.println("Aborted — nothing changed.")
		os.exit(0)
	}

	fmt.println("Renaming:")
	rename(opt)

	fmt.println()
	fmt.println("Done. Next:")
	fmt.println("  - review the diff (git diff), then build: cd app && ./run.sh   (run.bat on Windows)")
	fmt.println("  - the brand wordmark/suffix/repo live in app/src/views/brand.odin — tweak to taste")
	fmt.println("  - CHANGELOG.md / TODO.md / load-tests/RESULTS.md describe the example; prune them")
	fmt.println("  - once you're happy, delete tools/init (a one-time step) and commit")
}

// ---- rename -------------------------------------------------------------

rename :: proc(opt: Options) {
	name := opt.name

	// The name shows up three ways: as the app/machine name (`odin-htmx-skeleton`
	// is the Fly app, `odin-htmx-demo` the banner/README, `odin-htmx-e2e` the test
	// package) and as the binary (`demo`). These tokens are specific enough to
	// replace literally without touching prose.
	std := []Repl {
		{"demo.exe", strings.concatenate({name, ".exe"})}, // before bin/demo, so bin\demo.exe (Windows) is caught
		{"bin/demo", strings.concatenate({"bin/", name})},
		{"/app/demo", strings.concatenate({"/app/", name})},
		{"odin-htmx-skeleton", name},
		{"odin-htmx-demo", name},
		{"odin-htmx-e2e", strings.concatenate({name, "-e2e"})},
	}
	std_files := []string {
		"fly.toml",
		"Dockerfile",
		".github/workflows/ci.yml",
		"app/run.sh",
		"app/run.bat",
		"load-tests/run.sh",
		"e2e/fixtures.ts",
		"e2e/global-setup.ts",
		"e2e/helpers/server.ts",
		"e2e/package.json",
		"e2e/package-lock.json",
		"app/src/main.odin",
		"README.md",
		"app/README.md",
		"CLAUDE.md",
	}
	for f in std_files {
		edit(f, std)
	}

	// apollo-11's compose refers to the service by the bare `odin-htmx` (service /
	// image / container / volume names), so it needs that extra token.
	apollo := make([dynamic]Repl)
	append(&apollo, ..std)
	append(&apollo, Repl{"odin-htmx", name}) // also rewrites odin-htmx-data -> <name>-data
	edit("deploy/apollo-11/docker-compose.yml", apollo[:])

	// brand.odin holds the three display constants; rewrite each whole line so the
	// repo URL's `odin-htmx-skeleton` isn't caught by the token pass above.
	edit(
		"app/src/views/brand.odin",
		[]Repl {
			{`BRAND_WORDMARK :: "odin<b>·</b>htmx"`, strings.concatenate({`BRAND_WORDMARK :: "`, opt.wordmark, `"`})},
			{`BRAND_SUFFIX :: "Odin + HTMX"`, strings.concatenate({`BRAND_SUFFIX :: "`, opt.suffix, `"`})},
			{`BRAND_REPO :: "https://github.com/alexh95/odin-htmx-skeleton"`, strings.concatenate({`BRAND_REPO :: "`, opt.repo, `"`})},
		},
	)
}

// Read a file, apply the replacements, write it back if anything changed.
edit :: proc(path: string, repls: []Repl) {
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		fmt.printfln("  %-38s (skipped — not found)", path)
		return
	}
	s := string(data)
	total := 0
	for r in repls {
		c := strings.count(s, r.old)
		if c > 0 {
			s, _ = strings.replace_all(s, r.old, r.new)
			total += c
		}
	}
	if total == 0 {
		return
	}
	if werr := os.write_entire_file(path, s); werr != nil {
		fmt.eprintfln("  ERROR writing %s: %v", path, werr)
		os.exit(1)
	}
	fmt.printfln("  %-38s %d edit%s", path, total, total == 1 ? "" : "s")
}

// ---- args ---------------------------------------------------------------

parse_args :: proc(args: []string) -> Options {
	opt: Options
	i := 0
	for i < len(args) {
		a := args[i]
		switch {
		case a == "-y", a == "--yes":
			opt.yes = true
		case a == "--wordmark":
			opt.wordmark = next_arg(args, &i, "--wordmark")
		case a == "--suffix":
			opt.suffix = next_arg(args, &i, "--suffix")
		case a == "--repo":
			opt.repo = next_arg(args, &i, "--repo")
		case a == "-h", a == "--help":
			usage()
		case strings.has_prefix(a, "-"):
			fatal(fmt.tprintf("unknown flag %q", a))
		case:
			if opt.name != "" {
				fatal(fmt.tprintf("unexpected extra argument %q", a))
			}
			opt.name = a
		}
		i += 1
	}

	if opt.name == "" {
		usage()
	}
	if !valid_name(opt.name) {
		fatal("<new-name> must be lower-case letters, digits and dashes, starting with a letter (e.g. acme-crm)")
	}
	if strings.contains(opt.wordmark, `"`) || strings.contains(opt.suffix, `"`) || strings.contains(opt.repo, `"`) {
		fatal(`--wordmark / --suffix / --repo cannot contain a double-quote`)
	}
	// Defaults derived from the name.
	if opt.wordmark == "" {
		opt.wordmark = opt.name
	}
	if opt.suffix == "" {
		opt.suffix = title_case(opt.name)
	}
	if opt.repo == "" {
		opt.repo = strings.concatenate({"https://github.com/your-org/", opt.name})
	}
	return opt
}

next_arg :: proc(args: []string, i: ^int, flag: string) -> string {
	if i^ + 1 >= len(args) {
		fatal(fmt.tprintf("%s needs a value", flag))
	}
	i^ += 1
	return args[i^]
}

valid_name :: proc(s: string) -> bool {
	if len(s) == 0 || !(s[0] >= 'a' && s[0] <= 'z') {
		return false
	}
	for i in 0 ..< len(s) {
		c := s[i]
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}
	return true
}

// "acme-crm" -> "Acme Crm", a readable default for the <title> suffix.
title_case :: proc(name: string) -> string {
	parts := strings.split(name, "-")
	for p, i in parts {
		if len(p) > 0 {
			parts[i] = strings.concatenate({strings.to_upper(p[:1]), p[1:]})
		}
	}
	return strings.join(parts, " ")
}

confirm :: proc(prompt: string) -> bool {
	fmt.print(prompt)
	buf: [16]u8
	n, _ := os.read(os.stdin, buf[:])
	return n > 0 && (buf[0] == 'y' || buf[0] == 'Y')
}

usage :: proc() {
	fmt.eprintln("usage: odin run tools/init -- <new-name> [--wordmark W] [--suffix S] [--repo URL] [--yes]")
	fmt.eprintln("  <new-name>   lower-case machine name, e.g. acme-crm")
	fmt.eprintln("  --wordmark   topbar wordmark (inline HTML ok); default: <new-name>")
	fmt.eprintln("  --suffix     <title> suffix; default: Title Case of <new-name>")
	fmt.eprintln("  --repo       GitHub URL for the About page; default: a placeholder")
	fmt.eprintln("  --yes, -y    skip the confirmation prompt")
	os.exit(2)
}

fatal :: proc(msg: string) {
	fmt.eprintfln("init: %s", msg)
	os.exit(1)
}
