package chat_web

// Fixture for spike S0.10: chat links all four transports for its switch, so
// its EXTS unions theirs with what chat needs whatever the transport (D19).

import "../../../platform/web"
import chat_transport_multipart "../transport_multipart"
import chat_transport_poll "../transport_poll"
import chat_transport_sse "../transport_sse"
import chat_transport_ws "../transport_ws"

EXTS :: chat_transport_ws.EXTS + chat_transport_sse.EXTS + chat_transport_poll.EXTS + chat_transport_multipart.EXTS + bit_set[web.Ext]{.Pending, .Upsert, .Prompt, .Targets, .Download}
