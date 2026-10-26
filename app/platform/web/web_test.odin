package web

import "core:strings"
import "core:testing"

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
