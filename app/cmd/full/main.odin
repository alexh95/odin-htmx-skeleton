package main

// ---- full: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) ----------------------

import "../../platform/app"
import "../../platform/html"
import "../../platform/web"
import store_sqlite "../../platform/store/sqlite"
import about_web "../../features/about/web"
import home_web "../../features/home/web"
import accounts_store "store:accounts"
import identity "identity:."

// The home page's cards, in order: a dispatch table, like ROUTES.
HOME_CARDS := [?]html.Home_Card{}

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: home_web.EXTS + about_web.EXTS + identity.EXTS

main :: proc() {
	app.boot("full")
	identity.cli() // --hash-password
	home_web.init(HOME_CARDS[:], HOME)
	about_web.init(ABOUT)
	store_sqlite.init() // DB_PATH, SEED, MEMMODE: recorded here so --limits prints them
	app.check(HOSTS[:], nil, BUNDLE_EXTS)

	store_sqlite.open("full")
	store_sqlite.migrate("accounts", accounts_store.MIGRATIONS[:])
	identity.bootstrap() // the first admin, from ACCOUNTS_ADMIN_HASH

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2).
	app.serve(HOSTS[:], nil, &BRAND, web.Header_Set.Reporting)
	app.wait()
	app.shutdown()
	store_sqlite.close() // the writer's last batch, then the checkpoint
	app.exit()
}
