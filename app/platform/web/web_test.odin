package web

import "core:net"
import "core:strings"
import "core:testing"

// An IPv6 client is its /64 (M2-11); one a proxy reports IPv4-mapped is its IPv4 address,
// not a /64 shared with every other such client (M2-25).
@(test)
client_key_takes_a_64_and_a_mapped_ipv4 :: proc(t: ^testing.T) {
	v6 :: proc(b: [16]u8) -> net.Address { return transmute(net.IP6_Address)b }
	a := v6({0x20, 0x01, 0x0d, 0xb8, 0, 1, 0, 2, 0, 0, 0, 0, 0, 0, 0, 1})
	b := v6({0x20, 0x01, 0x0d, 0xb8, 0, 1, 0, 2, 0xff, 0xff, 0, 0, 0, 0, 0, 9})
	c := v6({0x20, 0x01, 0x0d, 0xb8, 0, 1, 0, 3, 0, 0, 0, 0, 0, 0, 0, 1})
	testing.expect(t, client_key(a) == client_key(b))
	testing.expect(t, client_key(a) != client_key(c))
	m1 := v6({0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 10, 0, 0, 1})
	m2 := v6({0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 10, 0, 0, 2})
	testing.expect(t, client_key(m1) != client_key(m2))
	testing.expect(t, client_key(m1) == client_key(net.IP4_Address{10, 0, 0, 1}))
}

// The policies security_init builds (§12.2): the base keeps 'self' and the
// pre-paint hash, a reporting profile ends with report-to, and the nonce class
// admits scripts by nonce or hash alone.
@(test)
csp_policies :: proc(t: ^testing.T) {
	security_init(.Reporting, nil)
	defer {
		delete(sec.csp)
		delete(sec.nonce_tail)
	}
	testing.expect(t, strings.has_prefix(sec.csp, "default-src 'self'; script-src 'self' 'sha256-"))
	testing.expect(t, strings.has_suffix(sec.csp, "frame-ancestors 'none'; report-to csp"))
	nonced := strings.concatenate({sec.nonce_head, "NONCE", sec.nonce_tail}, context.temp_allocator)
	script := nonced[strings.index(nonced, "script-src"):]
	script = script[:strings.index_byte(script, ';')]
	testing.expect(t, strings.has_prefix(script, "script-src 'nonce-NONCE' 'sha256-"))
	testing.expectf(t, !strings.contains(script, "'self'"), "the nonce class admits 'self': %s", script)
	testing.expect(t, strings.has_suffix(nonced, "; report-to csp"))
}
