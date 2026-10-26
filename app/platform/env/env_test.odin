package env

import "core:net"
import "core:testing"
import "core:time"

@(test)
parses_each_kind :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	ok :: proc(t: ^testing.T, row: Row, text: string) -> Value {
		v, problem := parse(row, text)
		testing.expectf(t, problem == "", "%s=%q: %s", row.name, text, problem)
		return v
	}
	bad :: proc(t: ^testing.T, row: Row, text: string) {
		_, problem := parse(row, text)
		testing.expectf(t, problem != "", "%s=%q should be refused", row.name, text)
	}

	testing.expect_value(t, ok(t, {name = "N", kind = .Int}, "8080").i, 8080)
	bad(t, {name = "N", kind = .Int}, "80a")
	testing.expect_value(t, ok(t, {name = "B", kind = .Bool}, "yes").i, 1)
	testing.expect_value(t, ok(t, {name = "B", kind = .Bool}, "0").i, 0)
	bad(t, {name = "B", kind = .Bool}, "maybe")
	testing.expect_value(t, time.Duration(ok(t, {name = "D", kind = .Duration}, "7d").i), 7 * 24 * time.Hour)
	testing.expect_value(t, time.Duration(ok(t, {name = "D", kind = .Duration}, "500ms").i), 500 * time.Millisecond)
	bad(t, {name = "D", kind = .Duration}, "5")
	bad(t, {name = "D", kind = .Duration}, "-5s")
	testing.expect_value(t, ok(t, {name = "S", kind = .Size}, "16MiB").i, 16 << 20)
	testing.expect_value(t, ok(t, {name = "S", kind = .Size}, "512").i, 512)
	bad(t, {name = "S", kind = .Size}, "16MB")
	bad(t, {name = "S", kind = .Size}, "99999999999999GiB")
	ok(t, {name = "E", kind = .Enum, choices = "single|ephemeral"}, "single")
	bad(t, {name = "E", kind = .Enum, choices = "single|ephemeral"}, "multi")
	testing.expect_value(t, ok(t, {name = "U", kind = .Int}, "").i, 0) // unset, no default

	c := ok(t, {name = "C", kind = .Cidrs}, "192.168.0.0/16, 10.0.0.1").cidrs
	testing.expect_value(t, len(c), 2)
	testing.expect(t, contains(c, net.IP4_Address{192, 168, 4, 20}))
	testing.expect(t, contains(c, net.IP4_Address{10, 0, 0, 1}))
	testing.expect(t, !contains(c, net.IP4_Address{10, 0, 0, 2}))
	testing.expect(t, !contains(c, net.IP4_Address{192, 169, 0, 1}))
	bad(t, {name = "C", kind = .Cidrs}, "192.168.0.0/33")
	bad(t, {name = "C", kind = .Cidrs}, "not-an-ip/8")
}
