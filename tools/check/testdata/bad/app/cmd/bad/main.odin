package main

import "../../platform/app"
import store_sqlite "../../platform/store/sqlite"
import x_store "store:x"

main :: proc() {
	app.boot("bad")
	store_sqlite.migrate("y", x_store.MIGRATIONS[:]) // x's migrations, named y's; z's never run
}
