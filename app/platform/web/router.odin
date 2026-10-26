package web

// ---- the router: one prefix map per host (§8.3; S7, D9) ------------------------
//
// Boot keys every mounted row by the literal start of its pattern, cut to its
// first one or two whole path segments: "/ui/ping" and "/ui/tab/(%w+)" are keys
// "/ui/ping" and "/ui/tab", "/contacts/(%d+)" is "/contacts". A request tries
// its first two segments, then its first one, then the "/" bucket (the root row,
// and rows whose first segment isn't literal, like "/favicon%.ico"), and inside
// a bucket the rows of its method in mount order: a literal row by comparing
// strings, a pattern row by its anchored Lua pattern, about 140 ns per row tried,
// ≤ 3 µs with ≤ 20 rows a feature (09 §4.4). Only a miss tries the other methods'
// rows, for the 405. Assets match at once: the skeleton registered /static/(.+)
// last, so every asset walked the whole table.
//
// A path no row of its method matches, but another method's does, is a 405 with
// Allow; anything else is the site's 404 (SK/app/src/routes.odin:67-69).

import "core:slice"
import "core:strings"
import "core:text/match"

import http "../../vendor/odin-http"
import "../obs"

Mounted :: struct {
	using row: Route,
	id:        string, // "GET /contacts/(%d+)"
	anchored:  string, // "^/contacts/(%d+)$"
	literal:   string, // the path itself when the pattern has no magic ("/favicon%.ico": "/favicon.ico")
	key:       string,
	obs:       obs.Route,
}

Router :: struct {
	buckets: map[string][dynamic]^Mounted,
	rows:    [dynamic]^Mounted, // every row, in mount order: --routes, robots, the boot checks
}

MAGIC :: "^$()%.[]*+-?"

// The row's bucket key: its first one or two whole literal segments, or "/".
// An escaped character ("%." in "/favicon%.ico") is literal.
key_of :: proc(pattern: string, allocator := context.allocator) -> string {
	l, all_literal := literal_start(pattern, allocator)
	if l == "/" && all_literal { return "/" }
	// Whole segments only: a segment the literal stops inside isn't a key.
	segs, end := 0, 0
	for i := 1; i <= len(l) && segs < 2; i += 1 {
		if i == len(l) {
			if all_literal { segs += 1; end = i }
			break
		}
		if l[i] == '/' {
			segs += 1
			end = i
		}
	}
	return l[:end] if end > 0 else "/"
}

// The pattern's literal start, escapes resolved, and whether that is all of it.
@(private)
literal_start :: proc(pattern: string, allocator := context.allocator) -> (lit: string, whole: bool) {
	b := strings.builder_make(allocator)
	for i := 0; i < len(pattern); i += 1 {
		c := pattern[i]
		if c == '%' && i + 1 < len(pattern) && !is_alnum(pattern[i + 1]) {
			strings.write_byte(&b, pattern[i + 1])
			i += 1
			continue
		}
		if strings.index_byte(MAGIC, c) >= 0 { return strings.to_string(b), false }
		strings.write_byte(&b, c)
	}
	return strings.to_string(b), true
}

@(private)
is_alnum :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

// At boot, on the main thread: the rows of one host, in mount order.
router_mount :: proc(r: ^Router, rows: []Route) {
	for row in rows {
		m := new(Mounted)
		m.row = row
		m.id = route_id(row)
		m.anchored = strings.concatenate({"^", row.pattern, "$"})
		if lit, whole := literal_start(row.pattern); whole { m.literal = lit }
		m.key = key_of(row.pattern)
		if m.key not_in r.buckets { r.buckets[m.key] = make([dynamic]^Mounted) }
		append(&r.buckets[m.key], m)
		append(&r.rows, m)
	}
}

// The row that answers `path` for `method`, with its captures in the request
// arena. Not found: `allow` lists the methods that would answer (405), or is
// empty (404).
router_find :: proc(r: ^Router, method: Method, path: string) -> (m: ^Mounted, params: []string, allow: []string) {
	keys: [3]string
	n := 0
	if s1 := segment_end(path, 1); s1 > 0 {
		if s2 := segment_end(path, 2); s2 > s1 { keys[n] = path[:s2]; n += 1 }
		keys[n] = path[:s1]
		n += 1
	}
	keys[n] = "/"
	n += 1

	caps: [match.MAX_CAPTURES]match.Match = ---
	for k in keys[:n] {
		bucket := r.buckets[k] or_continue
		for row in bucket {
			if row.method != method { continue }
			c := row_match(row, path, &caps)
			if c == 0 { continue }
			ps := make([]string, c - 1, context.temp_allocator)
			for cp, i in caps[1:c] { ps[i] = path[cp.byte_start:cp.byte_end] }
			return row, ps, nil
		}
	}
	others: [dynamic]string
	for k in keys[:n] {
		bucket := r.buckets[k] or_continue
		for row in bucket {
			if row.method == method || row_match(row, path, &caps) == 0 { continue }
			if others == nil { others = make([dynamic]string, context.temp_allocator) }
			append(&others, http.method_string(row.method))
			if row.method == .Get { append(&others, "HEAD") } // odin-http answers HEAD with the GET route
		}
	}
	if len(others) > 0 {
		slice.sort(others[:]) // a stable header, whatever the mount order
		uniq := slice.unique(others[:])
		return nil, nil, uniq
	}
	return nil, nil, nil
}

// How many captures the row's pattern made of `path`, the whole match first; 0: no match.
@(private)
row_match :: proc(row: ^Mounted, path: string, caps: ^[match.MAX_CAPTURES]match.Match) -> int {
	if row.literal != "" { return 1 if path == row.literal else 0 }
	c, err := match.find_aux(path, row.anchored, 0, true, caps)
	return c if err == .OK else 0
}

// The end of the path's nth segment ("/a/b/c", 2 → 4), or -1 past its last.
@(private)
segment_end :: proc(path: string, n: int) -> int {
	if len(path) < 2 || path[0] != '/' { return -1 }
	seen := 0
	for i := 1; i <= len(path); i += 1 {
		if i == len(path) || path[i] == '/' {
			seen += 1
			if seen == n { return i }
			if i == len(path) { return -1 }
		}
	}
	return -1
}
