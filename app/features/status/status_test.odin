package status

import "core:testing"

@(test)
the_tag_follows_the_states_alone :: proc(t: ^testing.T) {
	a := []Probe{{"hub", "ok", ""}, {"process", "ok", "up 3 s"}}
	b := []Probe{{"hub", "ok", ""}, {"process", "ok", "up 4 s"}}
	c := []Probe{{"hub", "down", ""}, {"process", "ok", "up 4 s"}}
	testing.expect_value(t, tag(a), tag(b)) // the uptime moved: nothing to send
	testing.expect(t, tag(b) != tag(c))
}
