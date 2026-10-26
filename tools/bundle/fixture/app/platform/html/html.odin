package html

// Fixture for spike S0.10: the layout picks its client and theme through two of
// the four collections on the build line (LC §3), so the compiler's file list
// names exactly one member of each.

import client "client:."
import theme "theme:."

CLIENT :: client.NAME
THEME :: theme.NAME
