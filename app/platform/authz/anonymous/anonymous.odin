package authz_anonymous

// ---- the default identity: everyone is the Guest ---------------------------
//
// A member of the `identity:` family (D35, LC §3): `minimal`, `skeleton` and
// `lab` build with it. Nothing reads or sets a cookie, its CLI answers nothing,
// and it has no routes, so its profiles mount no identity table.

import http "../../../vendor/odin-http"

import "../../authz"

NAME :: "anonymous"
SETS_COOKIE :: false

load_viewer :: proc(req: ^http.Request, res: ^http.Response) -> authz.Viewer {
	return authz.GUEST
}

// The identity's own CLI flags (--hash-password in the hashing identities).
cli :: proc() {}
