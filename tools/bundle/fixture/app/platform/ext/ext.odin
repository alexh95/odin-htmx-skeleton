package ext

// ---- htmx extensions (D19, D21) -----------------------------------------
//
// The closed set of htmx 4.0.0 extensions a page can load, and the four page
// bundles. Fixture copy for spike S0.10; M1 moves it to app/platform/ext. It is
// an L1 leaf that imports only core, so tools/bundle imports it too: the tool
// that writes a bundle header and the boot check that reads it share one table.

import "core:strings"

Ext :: enum {
	Sse,
	Ws,
	Multipart,
	Live,
	Pending,
	Browser_Indicator,
	Prompt,
	Preload,
	Ptag,
	History_Cache,
	Head,
	Upsert,
	Targets,
	Download,
	Compat_Htmx2,
	Compat_Alpine,
	Csp,
}

Exts :: bit_set[Ext]

// The name each file registers (htmx.registerExtension), which the htmx-config
// allowlist and the bundle header use (04 §2.2).
@(rodata)
NAMES := [Ext]string {
	.Sse               = "sse",
	.Ws                = "ws",
	.Multipart         = "hx-multipart",
	.Live              = "hx-live",
	.Pending           = "hx-pending",
	.Browser_Indicator = "browser-indicator",
	.Prompt            = "hx-prompt",
	.Preload           = "preload",
	.Ptag              = "ptag",
	.History_Cache     = "history-cache",
	.Head              = "hx-head",
	.Upsert            = "upsert",
	.Targets           = "hx-targets",
	.Download          = "download",
	.Compat_Htmx2      = "compat",
	.Compat_Alpine     = "alpine-compat",
	.Csp               = "hx-csp",
}

// The file under dist/ext/ in the htmx 4.0.0 tarball (04 §1.3).
@(rodata)
FILES := [Ext]string {
	.Sse               = "hx-sse.min.js",
	.Ws                = "hx-ws.min.js",
	.Multipart         = "hx-multipart.min.js",
	.Live              = "hx-live.min.js",
	.Pending           = "hx-pending.min.js",
	.Browser_Indicator = "hx-browser-indicator.min.js",
	.Prompt            = "hx-prompt.min.js",
	.Preload           = "hx-preload.min.js",
	.Ptag              = "hx-ptag.min.js",
	.History_Cache     = "hx-history-cache.min.js",
	.Head              = "hx-head.min.js",
	.Upsert            = "hx-upsert.min.js",
	.Targets           = "hx-targets.min.js",
	.Download          = "hx-download.min.js",
	.Compat_Htmx2      = "htmx-2-compat.min.js",
	.Compat_Alpine     = "hx-alpine-compat.min.js",
	.Csp               = "hx-csp.min.js",
}

// The lab-only four (D21): they ride in the fixed page bundles, never in Main.
LAB_ONLY :: Exts{.Live, .Csp, .Compat_Htmx2, .Compat_Alpine}

// ---- page bundles -------------------------------------------------------

Bundle :: enum {
	Main,
	Scripting,
	Compat_Htmx2,
	Compat_Alpine,
}

// Main is derived: the union of the EXTS lines the build reaches. The other
// three are fixed here, and a build gets one when a package it reaches names it
// on its one `BUNDLES ::` line (the scripting and compat features do).
@(rodata)
PAGE_EXTS := [Bundle]Exts {
	.Main          = {},
	.Scripting     = {.Csp, .Live, .Sse, .Ws, .Multipart, .Pending},
	.Compat_Htmx2  = {.Compat_Htmx2},
	.Compat_Alpine = {.Compat_Alpine},
}

// ---- the bundle header --------------------------------------------------
//
// Every bundle but a bare htmx.min.js starts `/* exts: sse, ws */` and a newline.
// The names are in load order: hx-csp first, because its hooks must run before
// any other extension's (11 §8.1), then the enum's order.

load_order :: proc(set: Exts, allocator := context.allocator) -> []Ext {
	out := make([dynamic]Ext, 0, card(set), allocator)
	if .Csp in set {
		append(&out, Ext.Csp)
	}
	for e in Ext {
		if e != .Csp && e in set {
			append(&out, e)
		}
	}
	return out[:]
}

// "sse, ws": the registration names in load order, as the header and the
// htmx-config allowlist write them.
list :: proc(set: Exts, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for e, i in load_order(set, context.temp_allocator) {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, NAMES[e])
	}
	return strings.to_string(b)
}

header :: proc(set: Exts, allocator := context.allocator) -> string {
	if set == {} {
		return ""
	}
	return strings.concatenate({"/* exts: ", list(set, context.temp_allocator), " */\n"}, allocator)
}

// A bundle with no header is htmx alone: the empty set.
parse_header :: proc(js: string) -> (set: Exts, ok: bool) {
	PREFIX :: "/* exts: "
	if !strings.has_prefix(js, PREFIX) {
		return {}, true
	}
	end := strings.index(js, " */\n")
	if end < 0 {
		return {}, false
	}
	list := js[len(PREFIX):end]
	for name in strings.split_iterator(&list, ", ") {
		found := false
		for n, e in NAMES {
			if n == name {
				set += {e}
				found = true
				break
			}
		}
		if !found {
			return {}, false
		}
	}
	return set, true
}
