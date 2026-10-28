package landing_views

// ---- landing: the views (PLAN §15.5) ------------------------------------------------------
//
// The catalog explorer and the init-command builder. The catalog is the generator's own
// output, but every value still goes through esc: it is data, not markup.

import "core:fmt"
import "core:slice"
import "core:strings"

import "../../../platform/html"
import landing ".."

w :: html.w
esc :: html.esc

// Where each profile runs (D2, D25): the witnesses on apollo's LAN, the skeleton's public
// witness on Fly, and Houston from M4.
Witness :: struct {
	name, href, text: string,
}

WITNESSES :: [?]Witness {
	{"lab", "/lab", "This site: the stream contract pages, the nonce class and the compatibility layers."},
	{"minimal", "https://starter-minimal.alexh95.com", "The one-page notes starter: the smallest profile, no SQLite."},
	{"streams", "https://starter-streams.alexh95.com", "Chat on four transports, the Inbox, the bot on its mock, ops and status."},
	{"skeleton", "https://odin-htmx.alexh95.com", "The 1.2.x contacts console, rebuilt from features at its exact URLs."},
	{"full", "https://houston.alexh95.com", "Houston, the showcase that runs every feature (from M4)."},
}

page :: proc(c: ^landing.Catalog, choice: landing.Choice) -> string {
	b := strings.builder_make(context.allocator)
	html.page_head(&b, "Starter", "odin-htmx-starter", "Server-rendered web apps in Odin and htmx 4, in one binary. Pick the features; the generator writes the project.")

	w(&b, `<section class="block"><h2 class="landing-h">Running now</h2><div class="landing-grid">`)
	for x in WITNESSES {
		w(&b, `<a class="card landing-card" href="`)
		esc(&b, x.href)
		w(&b, `"><h3>`)
		esc(&b, x.name)
		w(&b, `</h3><p class="muted">`)
		esc(&b, x.text)
		w(&b, `</p></a>`)
	}
	w(&b, `</div></section>`)

	w(&b, `<section class="block"><h2 class="landing-h">Make one</h2><form class="card landing-builder" hx-get="/landing/command" hx-target="#init-command" hx-trigger="change, input changed delay:300ms" action="/landing/command">`)
	w(&b, `<label class="field"><span>Name</span><input name="name" value="`)
	esc(&b, choice.name)
	fmt.sbprintf(&b, `" maxlength="%d" autocomplete="off" spellcheck="false"></label>`, landing.MAX_NAME)
	w(&b, `<fieldset class="field landing-features"><legend>Features</legend>`)
	for f in c.features {
		w(&b, `<label class="landing-pick"><input type="checkbox" name="f-`)
		esc(&b, f.name)
		w(&b, `" value="1"`)
		if slice.contains(choice.features, f.name) { w(&b, ` checked`) }
		w(&b, `> `)
		esc(&b, f.name)
		w(&b, `</label>`)
	}
	w(&b, `</fieldset><div class="landing-families">`)
	family(&b, "store", c.families.store)
	family(&b, "identity", c.families.identity)
	family(&b, "client", c.families.client)
	family(&b, "theme", c.families.theme)
	w(&b, `</div></form><div id="init-command" class="landing-out" aria-live="polite">`)
	command(&b, landing.plan(choice))
	w(&b, `</div></section>`)

	w(&b, `<section class="block"><h2 class="landing-h">Profiles</h2><div class="card table-scroll"><table class="table"><thead><tr><th>Profile</th><th>Store</th><th>Identity</th><th>Client</th><th>Theme</th><th>Features</th></tr></thead><tbody>`)
	for p in c.profiles {
		w(&b, `<tr><td><strong>`)
		esc(&b, p.name)
		w(&b, `</strong></td>`)
		for v in ([]string{p.store, p.identity, p.client, p.theme}) {
			w(&b, `<td>`)
			esc(&b, v)
			w(&b, `</td>`)
		}
		w(&b, `<td>`)
		esc(&b, strings.join(p.features, ", ", context.temp_allocator))
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></div></section>`)

	w(&b, `<section class="block"><h2 class="landing-h">Features</h2><div class="card table-scroll"><table class="table landing-features-table"><thead><tr><th>Feature</th><th>Lines</th><th>SQLite</th><th>Stores</th><th>Needs</th><th>Implementations</th><th>In</th></tr></thead><tbody>`)
	for f in c.features {
		w(&b, `<tr id="feature-`)
		esc(&b, f.name)
		w(&b, `"><td><strong>`)
		esc(&b, f.name)
		fmt.sbprintf(&b, `</strong></td><td>~%d</td><td>`, f.lines)
		esc(&b, sqlite_words(f.sqlite))
		for list in ([][]string{f.stores, f.deps, f.switched, f.profiles}) {
			w(&b, `</td><td>`)
			esc(&b, strings.join(list, ", ", context.temp_allocator) if len(list) > 0 else "—")
		}
		w(&b, `</td></tr>`)
	}
	w(&b, `</tbody></table></div><p class="muted landing-note">From <code>docs/catalog.json</code>: <code>odin run tools/init -- --list --json</code>.</p></section>`)
	return strings.to_string(b)
}

@(private)
sqlite_words :: proc(need: string) -> string {
	switch need {
	case "none":     return "keeps nothing"
	case "any":      return "either store"
	case "required": return "needs SQLite"
	case "never":    return "memory only"
	}
	return need
}

@(private)
family :: proc(b: ^strings.Builder, name: string, members: []string) {
	w(b, `<label class="field"><span>`)
	esc(b, name)
	w(b, `</span><select name="`)
	esc(b, name)
	w(b, `"><option value="">default</option>`)
	for m in members {
		w(b, `<option value="`)
		esc(b, m)
		w(b, `">`)
		esc(b, m)
		w(b, `</option>`)
	}
	w(b, `</select></label>`)
}

// The command a selection makes, and what it pulls in or why the generator would refuse it.
command :: proc(b: ^strings.Builder, p: landing.Plan) {
	w(b, `<pre class="landing-cmd"><code>`)
	esc(b, p.command)
	w(b, `</code></pre>`)
	if len(p.problems) > 0 {
		w(b, `<ul class="landing-problems">`)
		for x in p.problems {
			w(b, `<li>`)
			esc(b, x)
			w(b, `</li>`)
		}
		w(b, `</ul>`)
		return
	}
	w(b, `<p class="muted">`)
	fmt.sbprintf(b, "%d features, about %d lines, on the %s store; <code>/</code> is ", len(p.features), p.lines, p.store)
	esc(b, p.root)
	w(b, `.`)
	if len(p.added) > 0 {
		w(b, ` Pulled in: `)
		esc(b, strings.join(p.added, ", ", context.temp_allocator))
		w(b, `.`)
	}
	w(b, ` Run it with <code>--explain</code> first: the generator's own plan is the authority.</p>`)
}

command_html :: proc(p: landing.Plan) -> string {
	b := strings.builder_make(context.temp_allocator)
	command(&b, p)
	return strings.to_string(b)
}
