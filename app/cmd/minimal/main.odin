package main

// ---- minimal: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -------------------

import "../../platform/app"
import "../../platform/html"
import "../../platform/web"
import about_web "../../features/about/web"
import home_web "../../features/home/web"
import "../../features/notes"
import notes_web "../../features/notes/web"

// The home page's cards, in order: a dispatch table, like ROUTES.
HOME_CARDS := [?]html.Home_Card{notes_web.home_card}

// Every extension the main bundle needs (D19): none, so the bundle is htmx.min.js
// itself. Boot refuses a bundle whose header says otherwise.
BUNDLE_EXTS :: notes_web.EXTS + home_web.EXTS + about_web.EXTS

main :: proc() {
	app.boot("minimal")
	home_web.init(HOME_CARDS[:], HOME)
	about_web.init(ABOUT)
	app.check(HOSTS[:], nil, BUNDLE_EXTS)

	notes.seed() // the memory store is always new: the sample notes go in

	// The skeleton's exact header set, as minimal promises (§12.2).
	app.serve(HOSTS[:], nil, &BRAND, web.Header_Set.Skeleton)
	app.wait()
	app.shutdown()
	app.exit()
}
