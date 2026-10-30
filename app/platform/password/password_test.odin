package password

import "base:runtime"
import "core:strings"
import "core:testing"

// The buffer each thread keeps for argon lives as long as the thread; the test runner's tracker
// would count it, so each test gives it back.
@(private = "file")
release :: proc() {
	delete(buffer, runtime.heap_allocator())
	buffer = nil
}

@(test)
a_hash_verifies_its_password_alone :: proc(t: ^testing.T) {
	defer release()
	phc := hash("correct horse battery", context.temp_allocator)
	testing.expect(t, strings.has_prefix(phc, "$argon2id$v=19$m=19456,t=2,p=1$"), phc)
	testing.expect(t, verify("correct horse battery", phc))
	testing.expect(t, !verify("correct horse batterY", phc))
	testing.expect(t, !verify("", phc))
	// Two hashes of one password differ (a fresh salt each), and both verify.
	other := hash("correct horse battery", context.temp_allocator)
	testing.expect(t, other != phc)
	testing.expect(t, verify("correct horse battery", other))
}

@(test)
a_stored_string_names_no_cost_of_its_own :: proc(t: ^testing.T) {
	defer release()
	phc := hash("correct horse battery", context.temp_allocator)
	_, _, _, ok := decode(phc)
	testing.expect(t, ok)
	// Other parameters, versions, shapes: refused before any derive at their cost.
	bad := []string{
		strings.concatenate({"$argon2id$v=19$m=4194304,t=2,p=1$", phc[len("$argon2id$v=19$m=19456,t=2,p=1$"):]}, context.temp_allocator),
		strings.concatenate({"$argon2id$v=19$m=19456,t=99,p=1$", phc[len("$argon2id$v=19$m=19456,t=2,p=1$"):]}, context.temp_allocator),
		strings.concatenate({"$argon2i$v=19$m=19456,t=2,p=1$", phc[len("$argon2id$v=19$m=19456,t=2,p=1$"):]}, context.temp_allocator),
		strings.concatenate({"$argon2id$v=16$m=19456,t=2,p=1$", phc[len("$argon2id$v=19$m=19456,t=2,p=1$"):]}, context.temp_allocator),
		strings.concatenate({phc, "$x"}, context.temp_allocator),
		phc[:len(phc) - 1],
		"", "$", "$argon2id$v=19$m=19456,t=2,p=1$$",
		"$argon2id$v=19$m=19456,t=2,p=1,x=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
		"$argon2id$v=19$m=-1,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
	}
	for b in bad {
		_, _, _, bok := decode(b)
		testing.expectf(t, !bok, "%q decoded", b)
		testing.expectf(t, !verify("correct horse battery", b), "%q verified", b)
	}
	// OWASP's small preset is the one other a stored string may name.
	_, _, _, sok := decode("$argon2id$v=19$m=7168,t=5,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
	testing.expect(t, sok)
}

@(test)
lengths_are_checked_in_bytes :: proc(t: ^testing.T) {
	testing.expect_value(t, check("123456789"), Check.Too_Short)
	testing.expect_value(t, check("1234567890"), Check.Ok)
	testing.expect_value(t, check(strings.repeat("x", MAX_LEN, context.temp_allocator)), Check.Ok)
	testing.expect_value(t, check(strings.repeat("x", MAX_LEN + 1, context.temp_allocator)), Check.Too_Long)
}
