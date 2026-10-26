package chat_transport_sse

// Fixture for spike S0.10: a switched implementation declares the extension
// only it needs (X29).

import "../../../platform/ext"

EXTS :: bit_set[ext.Ext]{.Sse}
