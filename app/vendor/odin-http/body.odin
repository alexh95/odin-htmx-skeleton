package http

import "core:bufio"
import "core:io"
import "core:log"
import "core:net"
import "core:strings"

Body :: string

Body_Callback :: #type proc(user_data: rawptr, body: Body, err: Body_Error)

Body_Error :: bufio.Scanner_Error

/*
Retrieves the request's body.

If the request has the chunked Transfer-Encoding header set, the chunks are all read and returned.
Otherwise, the Content-Length header is used to determine what to read and return it.

`max_length` can be used to set a maximum amount of bytes we try to read, once it goes over this,
an error is returned.

Do not call this more than once.

**Tip** If an error is returned, easily respond with an appropriate error code like this, `http.respond(res, http.body_error_status(err))`.
*/
body :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	assert(req._body_ok == nil, "you can only call body once per request")

	enc_header, ok := headers_get_unsafe(req.headers, "transfer-encoding")
	if ok && strings.has_suffix(enc_header, "chunked") {
		_body_chunked(req, max_length, user_data, cb)
	} else {
		_body_length(req, max_length, user_data, cb)
	}
}

/*
Parses a URL encoded body, aka bodies with the 'Content-Type: application/x-www-form-urlencoded'.

Key&value pairs are percent decoded and put in a map.
*/
body_url_encoded :: proc(plain: Body, allocator := context.temp_allocator) -> (res: map[string]string, ok: bool) {

	insert :: proc(m: ^map[string]string, plain: string, keys: int, vals: int, end: int, allocator := context.temp_allocator) -> bool {
		has_value := vals != -1
		key_end   := vals - 1 if has_value else end
		key       := plain[keys:key_end]
		val       := plain[vals:end] if has_value else ""

		// PERF: this could be a hot spot and I don't like that we allocate the decoded key and value here.
		keye := (net.percent_decode(key, allocator) or_return) if strings.index_byte(key, '%') > -1 else key
		vale := (net.percent_decode(val, allocator) or_return) if has_value && strings.index_byte(val, '%') > -1 else val

		m[keye] = vale
		return true
	}

	count := 1
	for b in plain {
		if b == '&' { count += 1 }
	}

	queries := make(map[string]string, count, allocator)

	keys := 0
	vals := -1
	for b, i in plain {
		switch b {
		case '=':
			vals = i + 1
		case '&':
			insert(&queries, plain, keys, vals, i) or_return
			keys = i + 1
			vals = -1
		}
	}

	insert(&queries, plain, keys, vals, len(plain)) or_return

	return queries, true
}

// Returns an appropriate status code for the given body error.
body_error_status :: proc(e: Body_Error) -> Status {
	switch t in e {
	case bufio.Scanner_Extra_Error:
		switch t {
		case .Too_Long:                            return .Payload_Too_Large
		case .Too_Short, .Bad_Read_Count:          return .Bad_Request
		case .Negative_Advance, .Advanced_Too_Far: return .Internal_Server_Error
		case .None:                                return .OK
		case:
			return .Internal_Server_Error
		}
	case io.Error:
		switch t {
		case .EOF, .Unknown, .No_Progress, .Unexpected_EOF:
			return .Bad_Request
		case .Empty, .Short_Write, .Buffer_Full, .Short_Buffer,
		     .Invalid_Write, .Negative_Read, .Invalid_Whence, .Invalid_Offset,
		     .Invalid_Unread, .Negative_Write, .Negative_Count,
		     .Permission_Denied, .No_Size, .Closed:
			return .Internal_Server_Error
		case .None:
			return .OK
		case:
			return .Internal_Server_Error
		}
	case: unreachable()
	}
}


// "Decodes" a request body based on the content length header.
// Meant for internal usage, you should use `http.request_body`.
_body_length :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	req._body_ok = false

	len, ok := headers_get_unsafe(req.headers, "content-length")
	if !ok {
		cb(user_data, "", nil)
		return
	}

	// F-6: upstream parsed this with strconv.parse_int, which takes a sign, `_` separators and wraps
	// past 64 bits, and checked only the upper bound: "-5" (or 9223372036854775808) reached
	// `assert(n >= 0)` in scan_num_bytes and aborted the process. Only plain digits within `int`
	// pass; anything else answers 400 (Bad_Read_Count).
	ilen, lenok := parse_content_length(len)
	if !lenok {
		cb(user_data, "", .Bad_Read_Count)
		return
	}

	if max_length > -1 && ilen > max_length {
		cb(user_data, "", .Too_Long)
		return
	}

	if ilen == 0 {
		req._body_ok = true
		cb(user_data, "", nil)
		return
	}

	req._scanner.max_token_size = ilen

	req._scanner.split          = scan_num_bytes
	req._scanner.split_data     = rawptr(uintptr(ilen))

	req._body_ok = true
	scanner_scan(req._scanner, user_data, cb)
}

// RFC 9110 8.6: Content-Length = 1*DIGIT, within int.
parse_content_length :: proc(s: string) -> (n: int, ok: bool) {
	if len(s) == 0 { return }
	for c in transmute([]byte)s {
		if c < '0' || c > '9' { return 0, false }
		d := int(c - '0')
		if n > (max(int) - d) / 10 { return 0, false }
		n = n * 10 + d
	}
	return n, true
}

/*
"Decodes" a chunked transfer encoded request body.
Meant for internal usage, you should use `http.request_body`.

PERF: this could be made non-allocating by writing over the part of the body that contains the
metadata with the rest of the body, and then returning a slice of that, but it is some effort and
I don't think this functionality of HTTP is used that much anyway.

RFC 7230 4.1.3 pseudo-code:

length := 0
read chunk-size, chunk-ext (if any), and CRLF
while (chunk-size > 0) {
   read chunk-data and CRLF
   append chunk-data to decoded-body
   length := length + chunk-size
   read chunk-size, chunk-ext (if any), and CRLF
}
read trailer field
while (trailer field is not empty) {
   if (trailer field is allowed to be sent in a trailer) {
   	append trailer field to existing header fields
   }
   read trailer-field
}
Content-Length := length
Remove "chunked" from Transfer-Encoding
Remove Trailer from existing header fields
*/
_body_chunked :: proc(req: ^Request, max_length: int = -1, user_data: rawptr, cb: Body_Callback) {
	req._body_ok = false

	on_scan :: proc(s: rawptr, size_line: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s
		size_line := size_line

		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}
		if !count_framing(s, size_line) { return }

		// If there is a semicolon, discard everything after it,
		// that would be chunk extensions which we currently have no interest in.
		// F-14, F-16: whitespace may come only before the ';' (RFC 9112 BWS), and nothing
		// else may surround the size.
		if semi := strings.index_byte(size_line, ';'); semi > -1 {
			size_line = strings.trim_right(size_line[:semi], " \t")
		}

		size, ok := parse_chunk_size(size_line)
		if !ok {
			log.infof("Encountered an invalid chunk size when decoding a chunked body: %q", string(size_line))
			s.cb(s.user_data, "", .Bad_Read_Count)
			return
		}

		// start scanning trailer headers: field lines, where a bare LF is allowed (RFC 9112 2.2).
		if size == 0 {
			s.req._scanner.split = scan_lines
			scanner_scan(s.req._scanner, s, on_scan_trailer)
			return
		}

		if s.max_length > -1 && size > s.max_length - strings.builder_len(s.buf) {
			s.cb(s.user_data, "", .Too_Long)
			return
		}

		s.req._scanner.max_token_size = size

		s.req._scanner.split = scan_num_bytes

		#assert(size_of(int) == size_of(uintptr))
		s.req._scanner.split_data = rawptr(uintptr(size))

		scanner_scan(s.req._scanner, s, on_scan_chunk)
	}

	on_scan_chunk :: proc(s: rawptr, token: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s

		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}

		s.req._scanner.max_token_size = MAX_CHUNK_LINE
		s.req._scanner.split          = scan_crlf_lines

		strings.write_string(&s.buf, token)

		on_scan_empty_line :: proc(s: rawptr, token: string, err: bufio.Scanner_Error) {
			s := cast(^Chunked_State)s

			if err != nil {
				s.cb(s.user_data, "", err)
				return
			}
			// F-14: chunk data ends with a CRLF. Anything else is bad framing, a 400;
			// upstream asserted, so one request could take the process down.
			if !count_framing(s, token) { return }
			if len(token) != 0 {
				log.infof("Chunk data not followed by CRLF when decoding a chunked body")
				s.cb(s.user_data, "", .Bad_Read_Count)
				return
			}

			scanner_scan(s.req._scanner, s, on_scan)
		}

		scanner_scan(s.req._scanner, s, on_scan_empty_line)
	}

	on_scan_trailer :: proc(s: rawptr, line: string, err: bufio.Scanner_Error) {
		s := cast(^Chunked_State)s

		// F-16: a scan error (a line past the cap, a reset, the body timeout) is an error, not
		// the end of the trailers (M1-19).
		if err != nil {
			s.cb(s.user_data, "", err)
			return
		}

		// Headers are done, success.
		if len(line) == 0 {
			headers_delete_unsafe(&s.req.headers, "trailer")

			te_header := headers_get_unsafe(s.req.headers, "transfer-encoding")
			new_te_header := strings.trim_suffix(te_header, "chunked")

			s.req.headers.readonly = false
			headers_set_unsafe(&s.req.headers, "transfer-encoding", new_te_header)
			s.req.headers.readonly = true

			s.req._body_ok = true
			s.cb(s.user_data, strings.to_string(s.buf), nil)
			return
		}

		// F-14: trailer fields are read and discarded, at most MAX_TRAILERS lines (each
		// one capped by the scanner). Upstream parsed them into the request's headers,
		// which are read-only by now: header_parse asserted on the first trailer. Nothing
		// here reads one, and RFC 9110 6.5.1 lets a recipient drop them.
		if !count_framing(s, line) { return }
		s.trailers += 1
		if s.trailers > MAX_TRAILERS {
			log.infof("Too many trailer fields when decoding a chunked body")
			s.cb(s.user_data, "", .Too_Long)
			return
		}

		scanner_scan(s.req._scanner, s, on_scan_trailer)
	}

	Chunked_State :: struct {
		req:        ^Request,
		max_length: int,
		user_data:  rawptr,
		cb:         Body_Callback,

		buf:        strings.Builder,
		trailers:   int,
		framing:    int, // F-16: the bytes of size lines, line ends and trailers so far
	}

	// F-16: chunk framing counts against the cap as well as the data (the line ends as 2
	// bytes each), with at least MIN_FRAMING for a small cap. Upstream counted only the data,
	// so one-byte chunks with long size lines grew a request's buffer without bound (M1-18).
	count_framing :: proc(s: ^Chunked_State, line: string) -> bool {
		s.framing += len(line) + 2
		if s.max_length > -1 && s.framing > max(s.max_length, MIN_FRAMING) {
			log.infof("Too much chunk framing when decoding a chunked body")
			s.cb(s.user_data, "", .Too_Long)
			return false
		}
		return true
	}

	s := new(Chunked_State, context.temp_allocator)

	s.buf.buf.allocator = context.temp_allocator

	s.req        = req
	s.max_length = max_length
	s.user_data  = user_data
	s.cb         = cb

	s.req._scanner.max_token_size = MAX_CHUNK_LINE
	s.req._scanner.split          = scan_crlf_lines
	scanner_scan(s.req._scanner, s, on_scan)
}

// F-16: the longest chunk-size line or line end the decoder scans (Go's net/http allows
// 4096), and the framing a capped body may carry whatever its cap.
MAX_CHUNK_LINE :: 4096
MIN_FRAMING :: 4096

// F-16: a chunk-size line, or the end of chunk data, ended by CRLF only (RFC 9112 7.1).
// bufio.scan_lines also takes a bare LF, which a proxy that frames strictly reads differently
// (M1-20). A line not yet ended waits for more; at EOF the scanner answers the EOF.
@(private)
scan_crlf_lines :: proc(split_data: rawptr, data: []byte, at_eof: bool) -> (advance: int, token: []byte, err: bufio.Scanner_Error, final_token: bool) {
	for b, i in data {
		if b != '\n' { continue }
		if i == 0 || data[i - 1] != '\r' { return 0, nil, .Bad_Read_Count, false }
		return i + 1, data[:i - 1], nil, false
	}
	return 0, nil, nil, false
}

// F-14: the most trailer field lines a chunked body may carry before it is refused.
MAX_TRAILERS :: 32

// F-14's 15-digit bound keeps a chunk size below 2^60, which needs a 64-bit int (M1-21).
#assert(size_of(int) == 8)

// F-14: a chunk size is 1*HEXDIG (RFC 9112 7.1) and nothing else, at most 15 digits, so
// it can't wrap. strconv's parse took a sign and `_` separators, and wrapped past 64 bits.
@(private)
parse_chunk_size :: proc(s: string) -> (n: int, ok: bool) {
	// F-16: leading zeros don't count toward the 15 digits (M1-20).
	if len(s) == 0 || len(strings.trim_left(s, "0")) > 15 { return }
	for c in transmute([]byte)s {
		d: int
		switch c {
		case '0' ..= '9': d = int(c - '0')
		case 'a' ..= 'f': d = int(c - 'a') + 10
		case 'A' ..= 'F': d = int(c - 'A') + 10
		case:             return 0, false
		}
		n = n * 16 + d
	}
	return n, true
}
