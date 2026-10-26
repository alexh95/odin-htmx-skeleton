package main

// ---- skeleton: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) ------------------

import "../../platform/app"
import store_sqlite "../../platform/store/sqlite"
import about_web "../../features/about/web"
import contacts_web "../../features/contacts/web"
import dashboard_web "../../features/dashboard/web"
import gallery_web "../../features/gallery/web"
import contacts_store "store:contacts"

// Every extension the main bundle needs (D19): none, so the bundle is the
// skeleton's htmx.min.js itself, its crc32 name unchanged.
BUNDLE_EXTS :: dashboard_web.EXTS + gallery_web.EXTS + contacts_web.EXTS + about_web.EXTS

main :: proc() {
	app.boot("skeleton")
	about_web.init(ABOUT)
	app.check(HOSTS[:], nil, BUNDLE_EXTS)

	// The store (§8.6 step 5): a skeleton database (709bc94 or v1.1.1) is adopted
	// by contacts, whose first three migrations it already ran.
	store_sqlite.open("skeleton", legacy = "contacts")
	store_sqlite.migrate("contacts", contacts_store.MIGRATIONS[:])
	if store_sqlite.unowned() { contacts_web.seed() } // :memory:, or SEED=1: the demo rows, into empty tables

	app.serve(HOSTS[:], nil, &BRAND)
	app.wait()
	app.shutdown()
	store_sqlite.close() // the writer's last batch, then the checkpoint
	app.exit()
}
