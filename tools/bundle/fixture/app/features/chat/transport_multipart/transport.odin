package chat_transport_multipart

// Fixture for spike S0.10: a switched implementation declares the extension
// only it needs (X29).

import "../../../../../../../app/platform/ext"

EXTS :: bit_set[ext.Ext]{.Multipart}
