package bot_web

// Fixture for spike S0.10: browser-indicator for generation, sse and
// hx-multipart for its two deliveries, download for transcripts (PLAN §7.4).

import "../../../platform/web"

EXTS :: bit_set[web.Ext]{.Browser_Indicator, .Sse, .Multipart, .Download}
