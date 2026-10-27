package main

import "../../platform/app"
import store_sqlite "../../platform/store/sqlite"
import x_store "store:x"

// u isn't mounted, x is and isn't named, and there's no PAGE_BUNDLES for x's (exts).
BUNDLE_EXTS :: u_web.EXTS + y_web.EXTS

main :: proc() {
	app.boot("bad")
	store_sqlite.migrate("y", x_store.MIGRATIONS[:]) // x's migrations, named y's; z's never run
	hub.mount("main", ..TOPICS[:]) // without hub.init (topics)
	hub.mount("lab", ..TOPICS[:])  // a host bad doesn't have
}
