package wiki_web

// Fixture for spike S0.10: preload on wiki links, history-cache on pages (D21).

import "../../../platform/web"

EXTS :: bit_set[web.Ext]{.Preload, .History_Cache}
