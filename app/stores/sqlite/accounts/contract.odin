package accounts_store_sqlite

import m "../../../features/accounts/models"

// A drifted signature fails here, in this package, built or not (LC §3).
_ : m.Store_User_By_Name : user_by_name
_ : m.Store_User_By_Id : user_by_id
_ : m.Store_Session : session
_ : m.Store_Count_Admins : count_admins
_ : m.Store_Create_User : create_user
_ : m.Store_Login_Failed : login_failed
_ : m.Store_Open_Session : open_session
_ : m.Store_Touch_Session : touch_session
_ : m.Store_Close_Session : close_session
