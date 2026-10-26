package contacts_store_sqlite

import m "../../../features/contacts/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Page : page
_ : m.Store_Filter_Count : filter_count
_ : m.Store_Match : match
_ : m.Store_Related : related
_ : m.Store_Get : get
_ : m.Store_Stats : stats
_ : m.Store_Timeline : timeline
_ : m.Store_Write : write
_ : m.Store_Seed : seed
