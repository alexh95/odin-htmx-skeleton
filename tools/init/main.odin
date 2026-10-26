package main

// ---- init: rename this starter for a new project ------------------------
//
// A one-time scaffolding tool. Run it from the repo root after cloning the
// template:
//
//   odin run tools/init -- <new-name> [--wordmark "New·Name"] [--suffix "..."]
//                                     [--repo <url>] [--site <url>] [--yes]
//
// <new-name> is the machine name (lower-case letters, digits, dashes; starts
// with a letter), e.g. `acme-crm`. It becomes the Fly app, the docker-host
// container + volume and the test package's name. --wordmark / --suffix / --repo
// / --site set every profile's brand (app/cmd/<profile>/brand.odin), the social
// card's source and the favicon's label; sensible defaults are derived from
// <new-name>. The profiles are the selections: minimal is the one-page starter
// the old --minimal stripped down to, and composing others is M2's compose mode
// (PLAN §14).
//
// The tool is itself an Odin program — the skeleton's own tooling stays on the
// stack it teaches. It edits a fixed set of files (no directory walk), so what
// it touches is auditable right here. Every edit is planned in memory and must
// apply before anything is written (see plan.odin): init either does all of
// it or, naming each miss, none of it. Only the closing report walks the tree,
// read-only, to list what still names the upstream.

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

Options :: struct {
	name:     string,
	wordmark: string,
	suffix:   string,
	repo:     string,
	site:     string,
	yes:      bool,
}

main :: proc() {
	opt := parse_args(os.args[1:])
	if !os.exists("tools/init/main.odin") {
		fatal("run it from the repo root: every path it edits is relative to there")
	}
	// A second run would trip over every edit the first one made. Say so plainly
	// instead of listing them all.
	if brand, err := os.read_entire_file(brand_path(PROFILES[0]), context.allocator);
	   err == nil && !strings.contains(string(brand), strings.concatenate({`"`, upstream_repo(), `"`})) {
		fatal("this checkout is already renamed (the brand's repo isn't the upstream's); init runs once, on a fresh copy of the template")
	}

	// Plan first (read-only), so a checkout init no longer fits fails before
	// the prompt rather than after it.
	rename(opt)
	check()

	fmt.printfln("Rename this starter to %q:", opt.name)
	fmt.printfln("  Fly app / docker-host service      : %s", opt.name)
	fmt.printfln("  brand wordmark (topbar)            : %s", opt.wordmark)
	fmt.printfln("  title suffix (<title>)             : %s", opt.suffix)
	fmt.printfln("  GitHub repo (About page)           : %s", opt.repo)
	fmt.printfln("  canonical site URL (SEO tags)      : %s", opt.site)
	fmt.printfln("  in the brands of                   : %s", strings.join(PROFILES[:], ", ", context.temp_allocator))
	fmt.println()

	if !opt.yes && !confirm("Proceed? [y/N] ") {
		fmt.println("Aborted — nothing changed.")
		os.exit(0)
	}

	fmt.println("Applying:")
	commit()

	fmt.println()
	fmt.println("Done. Next:")
	fmt.println("  - review the diff (git diff), then build and run a profile: app/run.sh   (run.bat on")
	fmt.println("    Windows; PROFILE=minimal for the one-page starter), or ./build.sh <profile>")
	fmt.println("  - app/cmd/<profile>/brand.odin: home_title is a stand-in tagline; write the site's own")
	fmt.println("    (~60 chars, it's the search-result title). The wordmark, suffix, repo and the pages'")
	fmt.println("    copy live there too")
	fmt.printfln("  - SITE_URL is %s: point it at your real domain (site_url in brand.odin, or SITE_URL", opt.site)
	fmt.println("    in fly.toml)")
	fmt.println("  - app/platform/static/og.png, the social card, is still the upstream's: re-render it from")
	fmt.println("    tools/og/og.html (which now carries your name; the command is in the file)")
	fmt.println("  - app/platform/static/favicon.svg + favicon.ico are the upstream's mark: redraw them when you have one")
	fmt.println("  - bing_site_auth / indexnow_key are blank, so their routes 404 until you verify your site")
	fmt.println("  - deploy: infra/PLAN.md → Operator steps (Fly), or deploy/docker-host (any Docker host)")
	fmt.println("  - LICENSE is the upstream's zlib notice, which stays in source copies; add your own")
	fmt.println("    copyright for your changes")
	fmt.println("  - CHANGELOG.md / TODO.md / load-tests/RESULTS.md describe the example; prune them")
	fmt.println("  - once you're happy, delete tools/init (a one-time step) and commit")
	report_leftovers()
	if len(notes) > 0 {
		fmt.println()
		fmt.println("Notes for tools/init itself (harmless to this run):")
		for n in notes {
			fmt.printfln("  - %s", n)
		}
	}
}

// ---- leftovers ----------------------------------------------------------
//
// What still names the upstream once init is done: history it shouldn't
// rewrite (CHANGELOG, LICENSE), and anything the fixed file list doesn't know
// about. Listed rather than guessed at, so nothing is found by surprise later.

UPSTREAM_MARKS :: [?]string{"odin-htmx", "alexh95", "apollo-11"}

report_leftovers :: proc() {
	Hit :: struct {
		path:  string,
		lines: int,
	}
	hits: [dynamic]Hit
	root, _ := os.get_working_directory(context.allocator)
	w := os.walker_create(".")
	defer os.walker_destroy(&w)
	for info in os.walker_walk(&w) {
		if _, err := os.walker_error(&w); err != nil {
			continue
		}
		rel, _ := strings.replace_all(strings.trim_prefix(info.fullpath, root), `\`, "/")
		rel = strings.trim_prefix(strings.trim_left(rel, "/"), "./")
		if info.type == .Directory {
			switch info.name {
			case ".git", "node_modules", "odin-http", "bin", "build", "vendor", "results", "playwright-report", "test-results":
				os.walker_skip_dir(&w)
			}
			if rel == "tools/init" {
				os.walker_skip_dir(&w)
			}
			continue
		}
		data, err := os.read_entire_file(info.fullpath, context.temp_allocator)
		if err != nil || strings.index_byte(string(data), 0) >= 0 { // binary: og.png etc. are in the Next list
			continue
		}
		n := 0
		s := string(data)
		for line in strings.split_lines_iterator(&s) {
			for m in UPSTREAM_MARKS {
				if strings.contains(line, m) {
					n += 1
					break
				}
			}
		}
		if n > 0 {
			append(&hits, Hit{strings.clone(rel), n})
		}
		free_all(context.temp_allocator)
	}
	if len(hits) == 0 {
		return
	}
	slice.sort_by(hits[:], proc(a, b: Hit) -> bool {return a.path < b.path})
	fmt.println()
	fmt.println("Still naming the upstream (history to keep, or yours to edit):")
	for h in hits {
		fmt.printfln("  %-38s %d line%s", h.path, h.lines, h.lines == 1 ? "" : "s")
	}
}

xml_escape :: proc(s: string) -> string {
	t, _ := strings.replace_all(s, "&", "&amp;")
	t, _ = strings.replace_all(t, "<", "&lt;")
	t, _ = strings.replace_all(t, ">", "&gt;")
	return t
}

// "https://acme.example.com/" -> "acme.example.com", for the card's domain pill.
host_of :: proc(url: string) -> string {
	h := url
	if i := strings.index(h, "://"); i >= 0 {
		h = h[i + 3:]
	}
	return strings.trim_right(h, "/")
}

// ---- rename -------------------------------------------------------------

// The template's repo comes from tools/init/UPSTREAM, so a rename is one line there plus the brands'
// `repo` in the same commit, not a literal here as well (10 §5.3).
UPSTREAM :: #load("UPSTREAM", string)

// The template's repository, as every profile's brand.odin names it on a fresh copy.
upstream_repo :: proc() -> string {
	text := UPSTREAM
	for line in strings.split_lines_iterator(&text) {
		if strings.has_prefix(line, "repo ") {
			return strings.trim_space(line[len("repo "):])
		}
	}
	fatal("tools/init/UPSTREAM names no repo")
	return ""
}

// The profiles whose brands init renames: every app/cmd/<profile>/ the template ships. A fixed
// list, like every path init edits: one that's gone is a problem, and one it doesn't know about
// shows in the closing report.
PROFILES := [?]string{"skeleton", "minimal"}

brand_path :: proc(profile: string) -> string {
	return strings.concatenate({"app/cmd/", profile, "/brand.odin"}, context.temp_allocator)
}

rename :: proc(opt: Options) {
	name := opt.name
	suffix := xml_escape(opt.suffix)

	// Lines the token pass below would only half-rewrite, so they go first.
	edit(
		"README.md",
		[]Repl {
			// The upstream's own live instance: a fork has none yet.
			{"**Live demo: [odin-htmx.alexh95.com](https://odin-htmx.alexh95.com/)** — the whole thing, served by\none ~3 MB binary on a shared-cpu-1x machine.\n\n", ""},
		},
	)
	edit(
		"app/platform/static/favicon.svg",
		[]Repl {
			{`aria-label="odin-htmx"`, strings.concatenate({`aria-label="`, suffix, `"`})},
			{`<title>odin · htmx</title>`, strings.concatenate({`<title>`, suffix, `</title>`})},
		},
	)
	// The social card's source: the fork re-renders og.png from it (see the file).
	edit(
		"tools/og/og.html",
		[]Repl {
			{`<span class="name">odin<b>·</b>htmx</span>`, strings.concatenate({`<span class="name">`, opt.wordmark, `</span>`})},
			{`<h1>The <em>Odin + HTMX</em> skeleton</h1>`, strings.concatenate({`<h1><em>`, suffix, `</em></h1>`})},
			{`<span class="url">odin-htmx.alexh95.com</span>`, strings.concatenate({`<span class="url">`, host_of(opt.site), `</span>`})},
		},
	)

	// The name shows up as the app/machine name (`odin-htmx-skeleton` is the Fly
	// app, the docker-host service and the README; `odin-htmx-e2e` the test
	// package). These tokens are specific enough to replace literally without
	// touching prose. The canonical origin rides along: docs that quote the
	// upstream's should quote the fork's. The binaries are named by profile
	// (app/bin/<profile>, /app/server in the image), so they stay.
	std := []Repl {
		{"odin-htmx-skeleton", name},
		{"odin-htmx-e2e", strings.concatenate({name, "-e2e"})},
		{"https://odin-htmx.alexh95.com", opt.site},
	}
	std_files := []string {
		"fly.toml",
		"load-tests/README.md",
		"e2e/package.json",
		"e2e/package-lock.json",
		"README.md",
		"CLAUDE.md",
		"infra/PLAN.md",
		"deploy/docker-host/deploy.sh",
		"deploy/docker-host/compose.yaml",
		"deploy/docker-host/README.md",
	}
	hits := make([]int, len(std))
	for f in std_files {
		sweep(f, std, hits)
	}

	for n, k in hits {
		if n == 0 {
			problem("no file names %q any more; drop it from rename's tokens", std[k].old)
		}
	}

	// Each profile's brand.odin holds its site identity: whole fields, so the
	// repo URL isn't left to the token pass above.
	for p in PROFILES {
		path := brand_path(p)
		set_field(path, "wordmark", opt.wordmark)
		set_field(path, "suffix", opt.suffix)
		// A stand-in: the home <title> is the site's search-result title, and
		// saying what the fork is takes the fork (the Next list asks).
		set_field(path, "home_title", strings.concatenate({opt.suffix, " — built with Odin + HTMX"}))
		// The JSON-LD name of the code: "Odin + HTMX skeleton" is the upstream's.
		set_field(path, "source_name", opt.suffix)
		set_field(path, "repo", opt.repo) // the brand's, and the about page's
		set_field(path, "site_url", opt.site)
		// Blanked, never rewritten: a search-engine ownership token proves *this*
		// deployment is ours. A fork serving it would be advertising a stranger's
		// proof. Empty makes the route 404 until the fork verifies its own site.
		set_field(path, "bing_site_auth", "", optional = true)
		set_field(path, "indexnow_key", "", optional = true)
	}
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
		case a == "--site":
			opt.site = next_arg(args, &i, "--site")
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
	// They land inside Odin string literals, where either would end or escape it.
	if strings.contains_any(opt.wordmark, `"\`) ||
	   strings.contains_any(opt.suffix, `"\`) ||
	   strings.contains_any(opt.repo, `"\`) ||
	   strings.contains_any(opt.site, `"\`) {
		fatal(`--wordmark / --suffix / --repo / --site cannot contain a double-quote or a backslash`)
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
	// A deliberately obvious placeholder: left unset, every canonical tag and
	// sitemap entry the fork serves would still point at the upstream domain,
	// which tells Google the fork is a copy of someone else's page.
	if opt.site == "" {
		opt.site = strings.concatenate({"https://", opt.name, ".example.com"})
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
	fmt.eprintln("usage: odin run tools/init -- <new-name> [--wordmark W] [--suffix S] [--repo URL] [--site URL] [--yes]")
	fmt.eprintln("  <new-name>   lower-case machine name, e.g. acme-crm")
	fmt.eprintln("  --wordmark   topbar wordmark (inline HTML ok); default: <new-name>")
	fmt.eprintln("  --suffix     <title> suffix; default: Title Case of <new-name>")
	fmt.eprintln("  --repo       GitHub URL for the About page; default: a placeholder")
	fmt.eprintln("  --site       canonical origin (canonical tags, sitemap); default: https://<new-name>.example.com")
	fmt.eprintln("  --yes, -y    skip the confirmation prompt")
	os.exit(2)
}

fatal :: proc(msg: string) {
	fmt.eprintfln("init: %s", msg)
	os.exit(1)
}
