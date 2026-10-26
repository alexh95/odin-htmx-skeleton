package compat_web

// Fixture for spike S0.10: its two pages load the fixed compat bundles.

import "../../../platform/web"

BUNDLES :: bit_set[web.Bundle]{.Compat_Htmx2, .Compat_Alpine}
