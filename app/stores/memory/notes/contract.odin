package notes_store_memory

import m "../../../features/notes/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_Recent : recent
_ : m.Store_Add : add
_ : m.Store_Seed : seed
