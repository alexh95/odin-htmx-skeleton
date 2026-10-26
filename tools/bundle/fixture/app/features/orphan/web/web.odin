package orphan_web

// Fixture for spike S0.10: no profile imports it, so its lab-only extension
// must never reach a bundle.

import "../../../platform/web"

EXTS :: bit_set[web.Ext]{.Live}
