package html

// ---- behaviours: the one seam between markup and the client (D22, PLAN §12.4) -----------
//
// Markup never carries code. An element that needs client behaviour says which
// one through `behave`, and the build's client member supplies it:
//
//   client=hyperscript   _="install Tabs"       the behaviour in behaviours._hs
//   client=vanilla       data-behave="tabs"     app.js's delegated listener
//
// A behaviour with no vanilla twin ("" below) is hyperscript-only: under the
// vanilla client its element gets nothing, and every feature's core flow works
// without it (the progressive-enhancement rule). The hyperscript gate in app.js
// initialises only `install <Name>`, so a `_` that reaches a page any other way
// never runs (05 §5); escaping.spec checks every rendered `_` and `data-behave`.

import "core:strings"

Behaviour :: enum u8 {
	// twinned
	Tabs,
	Toast,
	Reset_On_Success,
	Dismiss,
	Search_Box,
	Range_Fill,
	Composer,
	Auto_Scroll,
	// hyperscript only
	Rel_Time,
	Copy_Text,
	Show_Password,
	Draggable,
	Drop_Zone,
	Palette,
	Term_Keys,
	Measure_Term,
	Resume,
	Scrubber,
	Otp_Input,
	Expire,
}

// One row per behaviour: its hyperscript name and its vanilla twin's ("" = none).
@(rodata)
BEHAVIOURS := [Behaviour]struct {
	hs, vanilla: string,
} {
	.Tabs             = {"Tabs", "tabs"},
	.Toast            = {"Toast", "toast"},
	.Reset_On_Success = {"ResetOnSuccess", "reset-on-success"},
	.Dismiss          = {"Dismiss", "dismiss"},
	.Search_Box       = {"SearchBox", "search-box"},
	.Range_Fill       = {"RangeFill", "range-fill"},
	.Composer         = {"Composer", "composer"},
	.Auto_Scroll      = {"AutoScroll", "auto-scroll"},
	.Rel_Time         = {"RelTime", ""},
	.Copy_Text        = {"CopyText", ""},
	.Show_Password    = {"ShowPassword", ""},
	.Draggable        = {"Draggable", ""},
	.Drop_Zone        = {"DropZone", ""},
	.Palette          = {"Palette", ""},
	.Term_Keys        = {"TermKeys", ""},
	.Measure_Term     = {"MeasureTerm", ""},
	.Resume           = {"Resume", ""},
	.Scrubber         = {"Scrubber", ""},
	.Otp_Input        = {"OtpInput", ""},
	.Expire           = {"Expire", ""},
}

// Writes the attribute that gives an element behaviour `x`, a leading space
// included, inside an open tag: `<div class="toast"` + behave + `>`.
behave :: proc(b: ^strings.Builder, x: Behaviour) {
	when CLIENT == "hyperscript" {
		w(b, ` _="install `)
		w(b, BEHAVIOURS[x].hs)
		w(b, `"`)
	} else {
		if BEHAVIOURS[x].vanilla == "" { return }
		w(b, ` data-behave="`)
		w(b, BEHAVIOURS[x].vanilla)
		w(b, `"`)
	}
}

// The same, as a string, for markup written as one literal.
behave_attr :: proc(x: Behaviour) -> string {
	b := strings.builder_make(context.temp_allocator)
	behave(&b, x)
	return strings.to_string(b)
}
