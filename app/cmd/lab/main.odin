package main

// ---- lab: the boot sequence, as plain calls (PLAN §7.2, §8.6, §8.7) -----------------------

import "../../platform/app"
import "../../platform/hub"
import "../../platform/web"
import about_web "../../features/about/web"
import compat_web "../../features/compat/web"
import landing_web "../../features/landing/web"
import lab_web "../../features/lab/web"
import scripting_web "../../features/scripting/web"

// Every extension the main bundle needs (D19). Boot refuses a bundle whose
// header says otherwise.
BUNDLE_EXTS :: landing_web.EXTS + lab_web.EXTS + scripting_web.EXTS + compat_web.EXTS + about_web.EXTS

// The fixed bundles its pages load besides Main (§12.1); boot refuses a build
// that didn't embed them.
PAGE_BUNDLES :: scripting_web.BUNDLES + compat_web.BUNDLES

main :: proc() {
	app.boot("lab")
	about_web.init(ABOUT)
	landing_web.init()
	lab_web.init()
	hub.init()
	hub.mount("main", ..TOPICS[:])
	app.check(HOSTS[:], JOBS[:], BUNDLE_EXTS, PAGE_BUNDLES)

	// The standard set, and browsers' CSP violation reports to /csp-report (§12.2).
	app.serve(HOSTS[:], JOBS[:], &BRAND, web.Header_Set.Reporting)
	app.wait()
	app.shutdown()
	app.exit()
}
