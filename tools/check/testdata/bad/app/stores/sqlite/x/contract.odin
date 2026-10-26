package x_store_sqlite

import m "../../../features/x/models"
import "../../../features/x" // a store never imports its domain

_ : m.Store_Get : get // Store_Put has no line

MIGRATIONS := [?]int{}

get :: proc(id: i64) -> int { return 0 }
