package main

// ---- lab: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -----------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import lab_web "../../features/lab/web"

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: lab_web.EXTS + about_web.EXTS

main :: proc() {
	app.boot("lab")
	about_web.init(ABOUT)
	hub.init()
	hub.mount("main", ..TOPICS[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS)

	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Standard)
	app.wait()
	app.shutdown()
	app.exit()
}
