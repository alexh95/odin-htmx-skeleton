package theme_lite

// ---- the theme family's lite member: one style, two schemes (D23) -------------
//
// `modern` with `midnight` and `daylight`, the same pre-paint script and the same
// picker as the full member. Its stylesheet is the full one with the regions
// marked `full-only` cut out, which tools/bundle does when it builds a lite
// profile's CSS, so the two never drift apart.

NAME :: "lite"

DEFAULT_STYLE :: "modern"
DEFAULT_SCHEME :: "midnight"

Style :: struct {
	id, label: string,
}

Scheme :: struct {
	style, id, label, swatch: string,
}

STYLES := [?]Style{{"modern", "Modern"}}

SCHEMES := [?]Scheme {
	{"modern", "midnight", "Midnight", "#7c5cff"},
	{"modern", "daylight", "Daylight", "#5b8cff"},
}
