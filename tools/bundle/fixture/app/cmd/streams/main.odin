package main

// Fixture for spike S0.10: the `streams` profile's main, cut to what the bundles
// need: its imports, BUNDLE_EXTS, and boot check 6 over the files prepare wrote
// with tools/bundle (BUNDLE_DIR, app/build by default). The app #loads each
// file under `when #exists`, so a build before prepare compiles (tools/bundle's
// scan build is one) and boot refuses it.

import "core:fmt"
import "../../platform/html"
import "../../platform/web"
import identity "identity:."
import bot_web "../../features/bot/web"
import chat_web "../../features/chat/web"
import notes_web "../../features/notes/web"

// Every extension the Main bundle needs (D19). Boot refuses a bundle whose /* exts: */ header differs.
BUNDLE_EXTS :: chat_web.EXTS + bot_web.EXTS
// The page bundles this binary serves: Main, and the fixed ones its packages name.
PAGE_BUNDLES :: bit_set[web.Bundle]{.Main}

BUNDLE_DIR :: #config(BUNDLE_DIR, "../../build")

when #exists(BUNDLE_DIR + "/streams/main.js") {
	MAIN_JS :: #load(BUNDLE_DIR + "/streams/main.js", string)
} else {
	MAIN_JS :: ""
}
when #exists(BUNDLE_DIR + "/streams/scripting.js") {
	SCRIPTING_JS :: #load(BUNDLE_DIR + "/streams/scripting.js", string)
} else {
	SCRIPTING_JS :: ""
}
when #exists(BUNDLE_DIR + "/streams/compat_htmx2.js") {
	COMPAT_HTMX2_JS :: #load(BUNDLE_DIR + "/streams/compat_htmx2.js", string)
} else {
	COMPAT_HTMX2_JS :: ""
}
when #exists(BUNDLE_DIR + "/streams/compat_alpine.js") {
	COMPAT_ALPINE_JS :: #load(BUNDLE_DIR + "/streams/compat_alpine.js", string)
} else {
	COMPAT_ALPINE_JS :: ""
}

main :: proc() {
	web.check_bundles("streams", BUNDLE_EXTS, PAGE_BUNDLES, {{.Main, MAIN_JS}, {.Scripting, SCRIPTING_JS}, {.Compat_Htmx2, COMPAT_HTMX2_JS}, {.Compat_Alpine, COMPAT_ALPINE_JS}})
	fmt.printfln("streams: identity %s, client %s, theme %s, notes store %s", identity.NAME, html.CLIENT, html.THEME, notes_web.STORE)
}
