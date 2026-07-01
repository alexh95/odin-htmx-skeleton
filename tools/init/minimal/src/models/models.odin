package models

// ---- domain model -------------------------------------------------------
//
// One trivial entity to get you started — replace it with yours. The whole
// stack (repository → service → view → controller) hangs off this single type;
// grep for `Note` to find every seam you touch when you swap it out.

Note :: struct {
	id:   int,
	body: string,
	at:   i64, // unix seconds, set at creation
}
