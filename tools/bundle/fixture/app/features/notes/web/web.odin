package notes_web

// Fixture for spike S0.10: a feature that loads no extension, so it declares no
// EXTS. Its store comes from the store family the build line selects.

import notes_store "store:notes"

STORE :: notes_store.NAME
