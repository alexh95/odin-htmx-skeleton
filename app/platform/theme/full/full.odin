package theme_full

// ---- the theme family's full member: 6 styles × 23 schemes (D23) -------------
//
// The skeleton's theme system. Two orthogonal axes carried on <html>:
// data-style (the treatment) and data-scheme (the palette within it). The
// stylesheet holds every style and scheme (app/platform/static/app.css, whole);
// platform/html renders the picker and the showroom from these tables.

NAME :: "full"

DEFAULT_STYLE :: "modern"
DEFAULT_SCHEME :: "midnight"

Style :: struct {
	id, label: string,
}

Scheme :: struct {
	style, id, label, swatch: string,
}

STYLES := [?]Style {
	{"modern", "Modern"},
	{"skeuo", "Skeuo"},
	{"terminal", "Terminal"},
	{"brutal", "Brutalist"},
	{"editorial", "Editorial"},
	{"arcade", "Arcade"},
}

SCHEMES := [?]Scheme {
	{"modern", "midnight", "Midnight", "#7c5cff"},
	{"modern", "daylight", "Daylight", "#5b8cff"},
	{"modern", "nebula", "Nebula", "#f472d0"},
	{"modern", "aurora", "Aurora", "#34d399"},
	{"modern", "ember", "Ember", "#fb923c"},
	{"modern", "sandstone", "Sandstone", "#d2622f"},
	{"modern", "ocean", "Ocean", "#38bdf8"},
	{"skeuo", "aqua", "Aqua", "#3b82f6"},
	{"skeuo", "graphite", "Graphite", "#8b95a3"},
	{"skeuo", "brass", "Brass", "#d8a64a"},
	{"terminal", "green", "Green", "#2bff66"},
	{"terminal", "amber", "Amber", "#ffb000"},
	{"terminal", "ibm", "IBM", "#8ab4ff"},
	{"terminal", "paper", "Paper", "#1f7a3d"},
	{"brutal", "paper", "Paper", "#2b46ff"},
	{"brutal", "ink", "Ink", "#111111"},
	{"brutal", "acid", "Acid", "#e6ff36"},
	{"editorial", "manuscript", "Manuscript", "#8a2f3a"},
	{"editorial", "sepia", "Sepia", "#9a5a2e"},
	{"editorial", "night", "Night", "#d99a5a"},
	{"arcade", "arcade", "Arcade", "#ff3df0"},
	{"arcade", "synthwave", "Synthwave", "#ff2d95"},
	{"arcade", "pop", "Pop", "#ff3b6b"},
}
