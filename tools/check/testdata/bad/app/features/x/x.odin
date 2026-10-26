package x

import "../../platform/web"   // a domain never imports platform/web
import y_store "store:y"     // nor another feature's store
import "store:x"
