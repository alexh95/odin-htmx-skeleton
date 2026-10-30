package jobs_store_sqlite

import m "../../../features/jobs/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Save : save
_ : m.Store_Recent : recent
_ : m.Store_Run : run
_ : m.Store_Fail_Lapsed : fail_lapsed
_ : m.Store_Prune : prune
