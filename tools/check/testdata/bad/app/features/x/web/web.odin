package x_web

import "../../y/web"   // a web package never imports another web package
import "../../z"

ROUTES := [?]web.Route {
	{.Get, "/", page, .Public, {}, 0},          // a root row inside a package's table
	{.Get, "/elsewhere", page, .Public, {}, 0}, // outside x's prefixes
	{.Get, "/legacy/page", page, .Public, {}, 0},
	{.Get, "/shared", page, .Public, {}, 0},
}

init :: proc() {}

page :: proc() {}
