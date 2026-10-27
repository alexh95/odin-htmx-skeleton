package hub

// A stand-in for the platform's hub: what the fixtures' TOPICS, hub.mount and
// hub.publish name.

Topic :: struct {
	family: string,
}

publish :: proc(topic, html: string) {}

mount :: proc(host: string, tables: ..[]Topic) {}

init :: proc() {}
