package main

// ---- init: rename this skeleton for a new project -----------------------
//
// A one-time scaffolding tool. Run it from the repo root after cloning the
// template:
//
//   odin run tools/init -- <new-name> [--wordmark "New·Name"] [--suffix "..."]
//                                     [--repo <url>] [--site <url>]
//                                     [--minimal] [--yes]
//
// <new-name> is the machine name (lower-case letters, digits, dashes; starts
// with a letter), e.g. `acme-crm`. It becomes the binary, the Fly app, the
// Docker image, the docker-host container + volume, the startup banner, and the
// package names. --wordmark / --suffix / --repo / --site set the brand constants
// the layout reads (see app/src/views/brand.odin), the social card's source and
// the favicon's label; sensible defaults are derived from <new-name>. --minimal
// additionally strips the contacts/events demo down to a one-page starter (see
// strip.odin).
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
	minimal:  bool,
	yes:      bool,
}

main :: proc() {
	opt := parse_args(os.args[1:])
	if !os.exists("tools/init/main.odin") {
		fatal("run it from the repo root: every path it edits is relative to there")
	}
	// A second run would trip over every edit the first one made. Say so plainly
	// instead of listing them all.
	if brand, err := os.read_entire_file("app/src/views/brand.odin", context.allocator);
	   err == nil && !strings.contains(string(brand), UPSTREAM_BRAND_REPO) {
		fatal("this checkout is already renamed (brand.odin's BRAND_REPO isn't the upstream's); init runs once, on a fresh copy of the template")
	}

	// Plan first (read-only), so a checkout init no longer fits fails before
	// the prompt rather than after it.
	rename(opt)
	if opt.minimal {
		strip_to_minimal(opt)
	}
	check()

	fmt.printfln("Rename this skeleton to %q:", opt.name)
	fmt.printfln("  binary / Fly app / image / service : %s", opt.name)
	fmt.printfln("  brand wordmark (topbar)            : %s", opt.wordmark)
	fmt.printfln("  title suffix (<title>)             : %s", opt.suffix)
	fmt.printfln("  GitHub repo (About page)           : %s", opt.repo)
	fmt.printfln("  canonical site URL (SEO tags)      : %s", opt.site)
	if opt.minimal {
		fmt.println("  + strip the contacts/events demo to a minimal one-page starter")
		if os.exists(DEV_DB[0]) {
			fmt.printfln("  + delete %s (+ -wal/-shm): the demo's local database, which the starter can't migrate", DEV_DB[0])
		}
	}
	fmt.println()

	if !opt.yes && !confirm("Proceed? [y/N] ") {
		fmt.println("Aborted — nothing changed.")
		os.exit(0)
	}

	fmt.println("Applying:")
	commit()

	fmt.println()
	fmt.println("Done. Next:")
	fmt.println("  - review the diff (git diff), then build: cd app && ./run.sh   (run.bat on Windows)")
	fmt.println("  - app/src/views/brand.odin: BRAND_HOME_TITLE is a stand-in tagline; write the site's own")
	fmt.println("    (~60 chars, it's the search-result title). The wordmark/suffix/repo live there too")
	fmt.printfln("  - SITE_URL is %s: point it at your real domain (brand.odin, or SITE_URL in fly.toml)", opt.site)
	fmt.println("  - app/static/og.png, the social card, is still the upstream's: re-render it from")
	fmt.println("    tools/og/og.html (which now carries your name; the command is in the file)")
	fmt.println("  - app/static/favicon.svg + favicon.ico are the upstream's mark: redraw them when you have one")
	fmt.println("  - BING_SITE_AUTH / INDEXNOW_KEY are blank, so their routes 404 until you verify your site")
	fmt.println("  - deploy: infra/PLAN.md → Operator steps (Fly), or deploy/docker-host (any Docker host)")
	fmt.println("  - LICENSE is the upstream's zlib notice, which stays in source copies; add your own")
	fmt.println("    copyright for your changes")
	if opt.minimal {
		fmt.println("  - CHANGELOG.md and TODO.md are new (TODO.md keeps this list); load-tests/RESULTS.md")
		fmt.println("    still holds the demo's numbers")
		fmt.println("  - if DB_PATH points at a database other than app/data.db, delete that too: it has the demo's schema")
	} else {
		fmt.println("  - CHANGELOG.md / TODO.md / load-tests/RESULTS.md describe the example; prune them")
	}
	fmt.println("  - once you're happy, delete tools/init (a one-time step) and commit")
	report_leftovers()
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
			case ".git", "node_modules", "odin-http", "bin", "vendor", "results", "playwright-report", "test-results":
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

UPSTREAM_BRAND_REPO :: `BRAND_REPO :: "https://github.com/alexh95/odin-htmx-skeleton"`

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
		"app/src/views/views.odin",
		[]Repl {
			// JSON-LD names the code "<suffix> skeleton"; a fork's code isn't one.
			{"w(&b, ` skeleton\",\"description\":\"`)", "w(&b, `\",\"description\":\"`)"},
		},
	)
	edit(
		"app/static/favicon.svg",
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

	// The name shows up two ways: as the app/machine name (`odin-htmx-skeleton` is
	// the Fly app, the banner and the README; `odin-htmx-e2e` the test package) and
	// as the binary (`demo`). These tokens are specific enough to replace literally
	// without touching prose. The canonical origin rides along: docs that quote
	// the upstream's should quote the fork's.
	std := []Repl {
		{"demo.exe", strings.concatenate({name, ".exe"})}, // before bin/demo, so bin\demo.exe (Windows) is caught
		{"bin/demo", strings.concatenate({"bin/", name})},
		{"/app/demo", strings.concatenate({"/app/", name})},
		{"odin-htmx-skeleton", name},
		{"odin-htmx-e2e", strings.concatenate({name, "-e2e"})},
		{"https://odin-htmx.alexh95.com", opt.site},
	}
	std_files := []string {
		"fly.toml",
		"Dockerfile",
		".github/workflows/ci.yml",
		"app/run.sh",
		"app/run.bat",
		"app/static/app.css",
		"load-tests/run.sh",
		"load-tests/README.md",
		"e2e/fixtures.ts",
		"e2e/global-setup.ts",
		"e2e/helpers/server.ts",
		"e2e/package.json",
		"e2e/package-lock.json",
		"app/src/main.odin",
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

	// The `minimal` CI job runs tools/init on the checkout to keep the --minimal
	// templates honest. That's the template's concern, not the fork's: a fork
	// deletes tools/init (and a minimal fork that grows past the Notes starter
	// would be overwritten by it), so either way the job would turn its CI red
	// and block the deploy that `needs` it.
	drop_job(".github/workflows/ci.yml", "minimal")
	if i := load(".github/workflows/ci.yml"); i >= 0 && strings.contains(changes[i].content, "tools/init") {
		problem(".github/workflows/ci.yml: still runs tools/init, which a fork deletes")
	}

	// brand.odin holds the site-identity constants; rewrite each whole line so the
	// repo URL's `odin-htmx-skeleton` isn't caught by the token pass above.
	edit(
		"app/src/views/brand.odin",
		[]Repl {
			{`BRAND_WORDMARK :: "odin<b>·</b>htmx"`, strings.concatenate({`BRAND_WORDMARK :: "`, opt.wordmark, `"`})},
			{`BRAND_SUFFIX :: "Odin + HTMX"`, strings.concatenate({`BRAND_SUFFIX :: "`, opt.suffix, `"`})},
			// A stand-in: the home <title> is the site's search-result title, and
			// saying what the fork is takes the fork (the Next list asks).
			{
				`BRAND_HOME_TITLE :: "Odin + HTMX skeleton — server-rendered HTML, one binary"`,
				strings.concatenate({`BRAND_HOME_TITLE :: "`, opt.suffix, ` — built with Odin + HTMX"`}),
			},
			{UPSTREAM_BRAND_REPO, strings.concatenate({`BRAND_REPO :: "`, opt.repo, `"`})},
			{`SITE_URL := "https://odin-htmx.alexh95.com"`, strings.concatenate({`SITE_URL := "`, opt.site, `"`})},
			// Blanked, never rewritten: a search-engine ownership token proves *this*
			// deployment is ours. A fork serving it would be advertising a stranger's
			// proof. Empty makes the route 404 until the fork verifies its own site.
			{`BING_SITE_AUTH :: "66E45151A5C32201FC3C8F86B6E094FF"`, `BING_SITE_AUTH :: ""`},
			{`INDEXNOW_KEY :: "e826b40f813548d2bd2e94885e506dfa"`, `INDEXNOW_KEY :: ""`},
		},
	)
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
		case a == "--minimal":
			opt.minimal = true
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
	fmt.eprintln("usage: odin run tools/init -- <new-name> [--wordmark W] [--suffix S] [--repo URL] [--yes]")
	fmt.eprintln("  <new-name>   lower-case machine name, e.g. acme-crm")
	fmt.eprintln("  --wordmark   topbar wordmark (inline HTML ok); default: <new-name>")
	fmt.eprintln("  --suffix     <title> suffix; default: Title Case of <new-name>")
	fmt.eprintln("  --repo       GitHub URL for the About page; default: a placeholder")
	fmt.eprintln("  --minimal    also strip the demo to a one-page starter")
	fmt.eprintln("  --yes, -y    skip the confirmation prompt")
	os.exit(2)
}

fatal :: proc(msg: string) {
	fmt.eprintfln("init: %s", msg)
	os.exit(1)
}
