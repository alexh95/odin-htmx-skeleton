package authz_anonymous

import "../../authz"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : authz.Load_Viewer : load_viewer
