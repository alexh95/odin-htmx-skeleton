package web

// Fixture for spike S0.10: the slice of platform/web that the bundle check
// needs. The real package re-exports ext the same way (X33).

import "core:fmt"
import "core:os"
import "../../../../../../app/platform/ext"

Ext :: ext.Ext
Bundle :: ext.Bundle

Embedded :: struct {
	bundle: Bundle,
	js:     string, // "" when the build found no file: prepare never ran
}

// Boot check 6 (D19): every bundle the binary loads must be embedded, and its
// header must name exactly the extensions the binary was compiled for:
// BUNDLE_EXTS for Main, the fixed set for the others. A mismatch means main's
// BUNDLE_EXTS and the build line disagree, or prepare is stale, and boot stops.
check_bundles :: proc(profile: string, bundle_exts: ext.Exts, pages: bit_set[Bundle], embedded: []Embedded) {
	failed := false
	for b in embedded {
		if b.bundle not_in pages {
			continue
		}
		want := b.bundle == .Main ? bundle_exts : ext.PAGE_EXTS[b.bundle]
		got, ok := ext.parse_header(b.js)
		switch {
		case b.js == "":
			fmt.eprintfln("%s: no %v bundle embedded: run prepare", profile, b.bundle)
			failed = true
		case !ok:
			fmt.eprintfln("%s: the %v bundle's header is malformed: run prepare", profile, b.bundle)
			failed = true
		case got != want:
			fmt.eprintfln("%s: the %v bundle carries %q, the binary wants %q: run prepare", profile, b.bundle, ext.list(got), ext.list(want))
			failed = true
		case:
			fmt.printfln("%s: %v bundle header matches (%d extensions, %d B)", profile, b.bundle, card(want), len(b.js))
		}
	}
	if failed {
		os.exit(1)
	}
}
