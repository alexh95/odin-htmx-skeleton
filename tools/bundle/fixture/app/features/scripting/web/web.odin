package scripting_web

// Fixture for spike S0.10: its pages load the fixed Scripting bundle, not
// Main, so it names the bundle on its one BUNDLES line instead of declaring EXTS.

import "../../../platform/web"

BUNDLES :: bit_set[web.Bundle]{.Scripting}
