package bot_backend_mock

// ---- the mock backend: the bot's default (PLAN §14.3, D31) ---------------------------------
//
// No model: a timer chain on the stream's loop answers with canned "under construction"
// and "TODO" lines, word by word, 30 to 120 ms apart, coalesced to at most 20 events a
// second as llama.cpp's binding will be, with llama's stats at the end. The same question
// gets the same answer when BOT_SEED is set; BOT_DELAY_MS fixes the delay (0: as fast as
// the loop goes). A generation lives on the loop that started it; `cancel` from any thread
// is posted there, so its timer is removed and its last event sent by that loop alone.

import "base:runtime"
import "core:hash"
import "core:math/rand"
import "core:nbio"
import "core:strings"
import "core:sync"
import "core:time"

import "../../../platform/env"
import "../../../platform/guard"
import "../../../platform/sys"
import "../../../platform/workers"
import m "../models"

NAME :: "mock"

ENV := [?]env.Row {
	{name = "BOT_SEED", kind = .Int, def = "0", doc = "the mock's seed: the same question gets the same answer; 0 = random"},
	{name = "BOT_DELAY_MS", kind = .Int, def = "-1", doc = "the mock's delay between words; -1 = 30-120 ms of jitter"},
}

@(private)
EMIT_EVERY_NS :: 50 * 1e6 // 20 Hz

@(private)
LINES := [?]string {
	"This answer is under construction: the real one arrives once llama.cpp runs on the LAN.",
	"TODO: put a model behind this. Until then the bot streams placeholder words, one at a time.",
	"Nothing here thinks yet. The page, the stream and the **Stop** button are real; these words are not.",
	"Under construction. Set `BOT_BACKEND=llama` and `BOT_LLAMA_URL` when a llama-server answers on the LAN.",
	"- TODO: the model\n- TODO: its context window\n- done: everything around them",
	"The mock picks a few canned lines and sends them word by word, with the stats llama.cpp would send.",
}

@(private)
Gen :: struct {
	id:      m.Bot_Gen_Id,
	sink:    m.Bot_Sink,
	words:   [dynamic]string, // into LINES: static strings
	next:    int,
	pending: strings.Builder, // words waiting for the next emit, each after its space
	prev:    string,
	op:      ^nbio.Operation, // the timer, while it is pending
	rng:     runtime.Default_Random_State,
	t0, first, last_emit: i64,
	tokens:  int,
}

@(private)
st: struct {
	mu:    guard.Mutex,
	gens:  map[m.Bot_Gen_Id]^Gen, // read from any thread by cancel; written on the gen's loop
	seq:   u64,
	seed:  u64,
	delay: int,
}

init :: proc() {
	env.record("BOT_", ENV[:])
	st.seed = u64(env.int_("BOT_SEED"))
	st.delay = env.int_("BOT_DELAY_MS")
	st.gens = make(map[m.Bot_Gen_Id]^Gen, heap())
}

health :: proc() -> m.Bot_Health {
	return {state = .Mock, model = NAME}
}

// Starts answering on the calling loop, which must be `sink.loop`.
start :: proc(req: m.Bot_Request, sink: m.Bot_Sink) -> m.Bot_Gen_Id {
	g := new(Gen, heap())
	g.id = sink.gen if sink.gen != 0 else m.Bot_Gen_Id(sync.atomic_add(&st.seq, 1) + 1)
	g.sink = sink
	g.sink.gen = g.id
	g.words.allocator = heap()
	g.pending = strings.builder_make(heap())
	question := req.history[len(req.history) - 1].text if len(req.history) > 0 else ""
	g.rng = rand.create(st.seed ~ hash.fnv64a(transmute([]byte)question) if st.seed != 0 else u64(sys.now_unix_ns()) ~ u64(g.id))
	gen := runtime.default_random_generator(&g.rng)
	for _ in 0 ..< 1 + rand.int_max(3, gen) {
		line := LINES[rand.int_max(len(LINES), gen)]
		if len(g.words) > 0 { append(&g.words, "\n\n") }
		rest := line
		for w in strings.split_iterator(&rest, " ") { append(&g.words, w) }
	}
	g.t0 = sys.mono_ns()
	guard.lock(&st.mu)
	st.gens[g.id] = g
	guard.unlock(&st.mu)
	schedule(g)
	return g.id
}

// Idempotent, from any thread: the generation stops with Bot_Done{.Stopped}.
cancel :: proc(id: m.Bot_Gen_Id) {
	guard.lock(&st.mu)
	g, ok := st.gens[id]
	loop: ^nbio.Event_Loop
	if ok { loop = g.sink.loop }
	guard.unlock(&st.mu)
	if !ok { return }
	box := new(m.Bot_Gen_Id, heap())
	box^ = id
	if !workers.post(loop, box, on_cancel) { free(box, heap()) }
}

// ---- on the generation's loop ------------------------------------------------------------------

@(private)
on_cancel :: proc(_: ^nbio.Operation, box: ^m.Bot_Gen_Id) {
	id := box^
	free(box, heap())
	guard.lock(&st.mu)
	g, ok := st.gens[id]
	guard.unlock(&st.mu)
	if !ok { return } // it finished first
	if g.op != nil {
		nbio.remove(g.op)
		g.op = nil
	}
	guard.call(proc(data: rawptr) { finish((^Gen)(data), .Stopped) }, g)
	free_all(context.temp_allocator)
}

@(private)
schedule :: proc(g: ^Gen) {
	d := st.delay
	if d < 0 {
		gen := runtime.default_random_generator(&g.rng)
		d = 30 + rand.int_max(91, gen)
	}
	g.op = nbio.timeout_poly(time.Duration(d) * time.Millisecond, g, tick)
}

@(private)
tick :: proc(_: ^nbio.Operation, g: ^Gen) {
	g.op = nil // fired: no longer removable
	guard.call(proc(data: rawptr) {
		g := (^Gen)(data)
		w := g.words[g.next]
		g.next += 1
		if g.prev != "" && g.prev != "\n\n" && w != "\n\n" { strings.write_byte(&g.pending, ' ') }
		strings.write_string(&g.pending, w)
		g.prev = w
		g.tokens += 1
		now := sys.mono_ns()
		if g.next >= len(g.words) {
			finish(g, .Eos)
			return
		}
		if now - g.last_emit >= EMIT_EVERY_NS { emit(g, now) }
		schedule(g)
	}, g)
	free_all(context.temp_allocator)
}

@(private)
emit :: proc(g: ^Gen, now: i64) {
	if strings.builder_len(g.pending) == 0 { return }
	if g.first == 0 { g.first = now }
	g.last_emit = now
	text := strings.clone(strings.to_string(g.pending), context.temp_allocator)
	strings.builder_reset(&g.pending)
	g.sink.on_event(g.sink.user, g.id, m.Bot_Token{text})
}

@(private)
finish :: proc(g: ^Gen, stop: m.Bot_Stop) {
	now := sys.mono_ns()
	emit(g, now)
	guard.lock(&st.mu)
	delete_key(&st.gens, g.id)
	guard.unlock(&st.mu)
	first := int((g.first - g.t0) / 1e6) if g.first != 0 else 0
	g.sink.on_event(g.sink.user, g.id, m.Bot_Done{stop = stop, tokens = g.tokens, ms_first_token = first, ms_total = int((now - g.t0) / 1e6)})
	delete(g.words)
	strings.builder_destroy(&g.pending)
	free(g, heap())
}

@(private)
heap :: proc() -> runtime.Allocator { return runtime.heap_allocator() }
