package lists_web

// Fixture for spike S0.10: the list stream, the pending add and upserted
// items (PLAN §12.1).

import "../../../platform/web"

EXTS :: bit_set[web.Ext]{.Sse, .Pending, .Upsert}
