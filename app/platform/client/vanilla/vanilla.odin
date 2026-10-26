package client_vanilla

// ---- the client family's vanilla member (D22) ---------------------------------
//
// Behaviours in plain JavaScript: app.js (beside this file) routes every click and
// change through one delegated listener, by data-* attributes, so swapped-in
// content needs no wiring and the CSP needs no inline handler. tools/bundle ships
// it as the profile's app.js. The hyperscript member (M2) is the other way to
// write the same behaviours.

NAME :: "vanilla"
