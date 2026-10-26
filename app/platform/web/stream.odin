package web

// ---- streams: the fork's F-1, for platform/stream -------------------------------
//
// A response that stays open after its handler returns (SSE, WebSocket,
// multipart). Re-exported so that platform/stream and platform/hub, which hold
// the protocols and the fan-out, never import odin-http (PLAN §5.1, §8.2).

import http "../../vendor/odin-http"

Stream               :: http.Stream
Stream_Kind          :: http.Stream_Kind
Stream_End           :: http.Stream_End
Stream_Data_Proc     :: http.Stream_Data_Proc
Stream_Close_Proc    :: http.Stream_Close_Proc
Stream_Shutdown_Proc :: http.Stream_Shutdown_Proc

STREAM_MAX_QUEUED :: http.STREAM_MAX_QUEUED

stream_begin          :: http.stream_begin
stream_write          :: http.stream_write
stream_write_string   :: http.stream_write_string
stream_end            :: http.stream_end
stream_queued         :: http.stream_queued
stream_would_overflow :: http.stream_would_overflow
stream_loop           :: http.stream_loop
