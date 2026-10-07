package main

// ---- the plan: every change, in memory, until all of them apply ---------
//
// Each step reads and updates the planned state of a file rather than the disk,
// so a later step sees an earlier one's result and nothing is written until the
// whole run has applied cleanly. A step that no longer fits the files (a
// replacement whose text is gone, a file that moved) records a problem instead;
// any problem aborts the run with nothing touched. The template drifting under
// init must break it loudly: a quiet skip is how a fork ends up half-renamed,
// or with a load driver pointing at scenarios it just deleted.

import "core:fmt"
import "core:os"
import "core:strings"

// A literal find/replace. Applied in order, so list the most specific first.
Repl :: struct {
	old, new: string,
}

Change :: struct {
	path:     string,
	content:  string,
	edits:    int,
	wrote:    bool, // replaced wholesale (or created)
	appended: bool,
	removed:  bool,
	optional: bool, // local state, not source: failing to remove it only warns
}

changes: [dynamic]Change
problems: [dynamic]string
notes: [dynamic]string // for init's maintainers; printed, never fatal

problem :: proc(format: string, args: ..any) {
	append(&problems, fmt.aprintf(format, ..args))
}

@(private = "file")
find :: proc(path: string) -> int {
	for c, i in changes {
		if c.path == path {
			return i
		}
	}
	return -1
}

// The planned content of `path`, read from disk the first time it's needed.
// -1 (and a problem) when there's nothing to edit.
load :: proc(path: string) -> int {
	if i := find(path); i >= 0 {
		if changes[i].removed {
			problem("%s: edited after an earlier step removed it", path)
			return -1
		}
		return i
	}
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		problem("%s: not found", path)
		return -1
	}
	append(&changes, Change{path = path, content = string(data)})
	return len(changes) - 1
}

// Every replacement must match at least once: each was written against a line
// that exists, and one that stopped matching means that line changed.
edit :: proc(path: string, repls: []Repl) {
	i := load(path)
	if i < 0 {
		return
	}
	s := changes[i].content
	for r in repls {
		n := strings.count(s, r.old)
		if n == 0 {
			problem("%s: no longer contains %q", path, r.old)
			continue
		}
		s, _ = strings.replace_all(s, r.old, r.new)
		changes[i].edits += n
	}
	changes[i].content = s
}

// A vocabulary pass: the same tokens over many files, each file holding only
// some of them. Holding every token to every file would just restate a grep, so
// the file must exist and each token must hit somewhere (`hits`, which the
// caller checks). A file with nothing left to rename isn't a miss, since nothing
// of the upstream is left in it either: it's a stale list entry, noted for
// whoever maintains init. The closing scan in main reports whatever is left.
sweep :: proc(path: string, repls: []Repl, hits: []int) {
	i := load(path)
	if i < 0 {
		return
	}
	s := changes[i].content
	total := 0
	for r, k in repls {
		n := strings.count(s, r.old)
		if n > 0 {
			s, _ = strings.replace_all(s, r.old, r.new)
			hits[k] += n
			total += n
		}
	}
	if total == 0 {
		append(&notes, fmt.aprintf("%s has nothing to rename any more; drop it from rename's file list", path))
	}
	changes[i].content = s
	changes[i].edits += total
}

// Remove a job from a GitHub Actions workflow: its block, the comment block
// directly above it, and its name from every `needs: [...]` list. Line-based,
// not a YAML parse, so it leans on the workflow's shape (jobs indented two
// spaces, needs in flow form); anything else is a problem, not a guess.
drop_job :: proc(path, job: string) {
	i := load(path)
	if i < 0 {
		return
	}
	lines := strings.split(changes[i].content, "\n")
	key := fmt.tprintf("  %s:", job)
	at := -1
	for l, n in lines {
		if strings.trim_right_space(l) == key {
			at = n
			break
		}
	}
	if at < 0 {
		problem("%s: no `%s` job to remove", path, job)
		return
	}
	first := at
	for first > 0 && strings.has_prefix(lines[first - 1], "  #") {
		first -= 1
	}
	// Its body is everything indented deeper (blank lines included), up to the
	// next job or that job's comment block.
	last := at + 1
	for last < len(lines) && (strings.trim_space(lines[last]) == "" || strings.has_prefix(lines[last], "   ")) {
		last += 1
	}

	kept := make([dynamic]string)
	append(&kept, ..lines[:first])
	append(&kept, ..lines[last:])
	for &l in kept {
		t := strings.trim_space(l)
		if !strings.has_prefix(t, "needs:") || !strings.contains(t, job) {
			continue
		}
		open := strings.index_byte(l, '[')
		close := strings.last_index_byte(l, ']')
		if open < 0 || close < open {
			problem("%s: can't drop %q from %q; edit it by hand", path, job, t)
			continue
		}
		names := make([dynamic]string)
		for n in strings.split(l[open + 1:close], ",") {
			if strings.trim_space(n) != job {
				append(&names, strings.trim_space(n))
			}
		}
		l = strings.concatenate({l[:open + 1], strings.join(names[:], ", "), l[close:]})
		changes[i].edits += 1
	}
	s := strings.join(kept[:], "\n")
	if strings.contains(s, fmt.tprintf("needs.%s", job)) {
		problem("%s: still refers to needs.%s after removing the job", path, job)
	}
	changes[i].content = s
	changes[i].edits += 1
}

put :: proc(path, content: string) {
	i := find(path)
	if i < 0 {
		append(&changes, Change{path = path})
		i = len(changes) - 1
	}
	changes[i].content = content
	changes[i].wrote = true
	changes[i].removed = false
}

append_to :: proc(path, extra: string) {
	i := load(path)
	if i < 0 {
		return
	}
	changes[i].content = strings.concatenate({changes[i].content, extra})
	changes[i].appended = true
}

// A file init expects to delete. Missing means the template moved on and the
// list here is stale, which is a problem like any other miss.
remove :: proc(path: string) {
	i := find(path)
	if i < 0 {
		if !os.exists(path) {
			problem("%s: not found (nothing to remove)", path)
			return
		}
		append(&changes, Change{path = path})
		i = len(changes) - 1
	}
	changes[i].removed = true
}

// Local, untracked state (a dev database) that may or may not be there.
remove_if_present :: proc(path: string) -> bool {
	if !os.exists(path) {
		return false
	}
	append(&changes, Change{path = path, removed = true, optional = true})
	return true
}

// ---- apply --------------------------------------------------------------

// Abort with the full list of misses, before anything is written.
check :: proc() {
	if len(problems) == 0 {
		return
	}
	fmt.eprintfln("init: %d step%s no longer fit this checkout; nothing was changed:", len(problems), len(problems) == 1 ? "" : "s")
	for p in problems {
		fmt.eprintfln("  - %s", p)
	}
	fmt.eprintln("If init already ran here, start again from a clean checkout: it runs once.")
	fmt.eprintln("Otherwise the template changed under it; tools/init needs updating to match.")
	os.exit(1)
}

commit :: proc() {
	for c in changes {
		switch {
		case c.removed:
			if err := os.remove(c.path); err != nil {
				if c.optional {
					fmt.printfln("  WARNING: could not remove %s (%v); delete it before the next run", c.path, err)
					continue
				}
				fmt.eprintfln("  ERROR removing %s: %v", c.path, err)
				os.exit(1)
			}
			fmt.printfln("  removed  %s", c.path)
		case c.wrote, c.appended, c.edits > 0:
			if err := os.write_entire_file(c.path, c.content); err != nil {
				fmt.eprintfln("  ERROR writing %s: %v", c.path, err)
				os.exit(1)
			}
			if c.wrote {
				fmt.printfln("  wrote    %s", c.path)
			} else if c.appended {
				fmt.printfln("  appended %s", c.path)
			} else {
				fmt.printfln("  %-38s %d edit%s", c.path, c.edits, c.edits == 1 ? "" : "s")
			}
		}
	}
}
