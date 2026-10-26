package video_web

// Fixture for spike S0.10: preload on cards, history-cache on the library,
// hx-head for og:video (D21).

import "../../../platform/web"

EXTS :: bit_set[web.Ext]{.Preload, .History_Cache, .Head}
