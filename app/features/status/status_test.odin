package status

import "core:testing"

@(test)
the_tag_follows_the_states_alone :: proc(t: ^testing.T) {
	a := []Probe{{"hub", "ok", "", false}, {"process", "ok", "up 3 s", false}}
	b := []Probe{{"hub", "ok", "", false}, {"process", "ok", "up 4 s", false}}
	c := []Probe{{"hub", "down", "", false}, {"process", "ok", "up 4 s", false}}
	testing.expect_value(t, tag(a), tag(b)) // the uptime moved: nothing to send
	testing.expect(t, tag(b) != tag(c))
}

@(test)
probes_parse_names_and_hosts_and_skip_the_rest :: proc(t: ^testing.T) {
	ps := parse_probes("minimal=starter-minimal:8080, streams = starter-streams:8080,Bad=x:1,nohost=,noport=host,<b>=h:1")
	defer {
		for p in ps { delete(p.name); delete(p.host) }
		delete(ps)
	}
	testing.expect_value(t, len(ps), 2)
	testing.expect_value(t, ps[0].name, "minimal")
	testing.expect_value(t, ps[1].host, "starter-streams:8080")
	testing.expect_value(t, ps[1].state, "checking")
}
