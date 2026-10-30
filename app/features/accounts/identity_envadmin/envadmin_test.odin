package accounts_identity_envadmin

import "core:testing"

// The cookie holds while its MAC is the key's and its end hasn't come; a changed byte, an
// ended cookie and a rotated key are a guest.
@(test)
the_cookie_is_signed_and_ends :: proc(t: ^testing.T) {
	key := [32]byte{0 = 1, 1 = 2, 2 = 3}
	other := [32]byte{0 = 9}
	value := sign(key[:], 1000, 2000)
	issued, ok := read(value, key[:], 1500)
	testing.expect(t, ok && issued == 1000)

	_, ok = read(value, key[:], 2000)
	testing.expect(t, !ok) // ended
	_, ok = read(value, key[:], 999)
	testing.expect(t, !ok) // issued in the future: not one of ours
	_, ok = read(value, other[:], 1500)
	testing.expect(t, !ok) // a new key signs everyone out

	tampered := transmute([]byte)string(value)
	forged := make([]byte, len(tampered), context.temp_allocator)
	copy(forged, tampered)
	forged[0] = '0' // issued later than it was
	_, ok = read(string(forged), key[:], 1500)
	testing.expect(t, !ok)
	_, ok = read("1000.2000", key[:], 1500)
	testing.expect(t, !ok) // no MAC
	_, ok = read("", key[:], 1500)
	testing.expect(t, !ok)
}
