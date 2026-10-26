import crypto from 'node:crypto';
import http from 'node:http';
import net from 'node:net';

// The lab specs' Node-side clients (from spike S0.3's harness, docs/spikes/S0.3.md): plain
// HTTP with chunk times, an SSE reader, and a raw WebSocket that can send what browsers never
// send. They talk to the worker's server (fixtures.ts) or to one a spec starts itself.

export const HOST = '127.0.0.1';
export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
// Keys the lab takes are 1-40 of [a-z0-9-].
export const uid = (p: string) => `${p}-${crypto.randomBytes(4).toString('hex')}`;

export type Got = { status: number; headers: http.IncomingHttpHeaders; body: string; times: number[]; reused: boolean };

// Plain requests reuse their sockets: the slow-consumer and ring checks send hundreds, and a
// fresh connection each leaves one in TIME_WAIT, which runs Windows out of ephemeral ports.
const pool = new http.Agent({ keepAlive: true, maxSockets: 64 });

export function get(port: number, p: string, opts: { agent?: http.Agent; headers?: http.OutgoingHttpHeaders } = {}): Promise<Got> {
  return new Promise((res, rej) => {
    const t0 = performance.now();
    const req = http.get({ host: HOST, port, path: p, agent: opts.agent ?? pool, headers: opts.headers }, (r) => {
      const chunks: Buffer[] = []; const times: number[] = [];
      r.on('data', (c) => { chunks.push(c); times.push(Math.round(performance.now() - t0)); });
      r.on('end', () => res({ status: r.statusCode ?? 0, headers: r.headers, body: Buffer.concat(chunks).toString(), times, reused: req.reusedSocket }));
    });
    req.on('error', rej);
    req.setTimeout(10_000, () => req.destroy(new Error('timeout')));
  });
}

export function post(port: number, p: string, form: Record<string, string> = {}): Promise<number> {
  const body = new URLSearchParams(form).toString();
  return new Promise((res, rej) => {
    const req = http.request({
      host: HOST, port, path: p, method: 'POST', agent: pool,
      headers: { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(body) },
    }, (r) => { r.resume(); r.on('end', () => res(r.statusCode ?? 0)); });
    req.on('error', rej);
    req.end(body);
  });
}

// A line to `lab.feed:<key>` (id and text: the lab escapes the text into the feed's
// fragment), or a message to `lab.room:<key>`.
export const publish = (port: number, key: string, id: string, text = `msg ${id}`) =>
  post(port, `/lab/publish?t=lab.feed:${key}`, { id, text });
export const say = (port: number, room: string, text: string) => post(port, `/lab/publish?t=lab.room:${room}`, { text });
// Ends a topic's streams as a kick does: SSE gets `kicked`, a socket closes with `code`.
export const closeTopic = (port: number, topic: string, code = 1000) =>
  post(port, `/lab/close?t=${encodeURIComponent(topic)}&code=${code}`);

export type Stats = {
  os: string; cursor: string; loops: number; loops_with_subs: number; open: number;
  ended: Record<string, number>; connects: Record<string, number>;
};
export const stats = async (port: number): Promise<Stats> => JSON.parse((await get(port, '/lab/stats')).body);

// ---- SSE --------------------------------------------------------------------------------------

export type Ev = { id?: string; event?: string; data: string };

// Reads events until `count` arrive or `ms` pass. The parser splits lines on CRLF, CR and LF, as
// the SSE spec and hx-sse do, so a raw CR from the server would show up here as an injected field.
export function sse(port: number, p: string, { count = 3, ms = 3000, headers = {} as http.OutgoingHttpHeaders } = {}): Promise<Ev[]> {
  return new Promise((res) => {
    const events: Ev[] = []; let buf = ''; let cur: Ev = { data: '' }; let hasData = false;
    const done = () => { req.destroy(); res(events); };
    const req = http.get({ host: HOST, port, path: p, headers }, (r) => {
      r.setEncoding('utf8');
      r.on('data', (c: string) => {
        buf += c;
        const lines = buf.split(/\r\n|\r|\n/);
        buf = lines.pop() ?? '';
        for (const line of lines) {
          if (line === '') {
            if (hasData || cur.event || cur.id) events.push(cur);
            cur = { data: '' }; hasData = false;
            if (events.length >= count) return done();
            continue;
          }
          if (line.startsWith(':')) continue;
          const i = line.indexOf(':');
          const k = i < 0 ? line : line.slice(0, i);
          let v = i < 0 ? '' : line.slice(i + 1);
          if (v.startsWith(' ')) v = v.slice(1);
          if (k === 'data') { cur.data += (hasData ? '\n' : '') + v; hasData = true; }
          else if (k === 'event') cur.event = v;
          else if (k === 'id') cur.id = v;
        }
      });
    });
    req.on('error', () => {});
    setTimeout(done, ms);
  });
}

export const seqOf = (id?: string) => Number((id ?? '').split('-')[1]);
export const epochOf = (id?: string) => (id ?? '').split('-')[0];

// ---- a raw WebSocket client, to send what browsers never send ------------------------------------

export type Frame = { op: number; fin: boolean; masked: boolean; payload: Buffer; code?: number | null };
export type RawWs = {
  s: net.Socket; status: number; head: string; acceptOk: boolean;
  send(op: number, payload: string | Buffer | Uint8Array, o?: { fin?: boolean; mask?: boolean; rsv?: number }): void;
  next(ms?: number): Promise<Frame | null>;
  closed: Promise<unknown>;
};

export function wsRaw(port: number, p: string, headers: Record<string, string | null> = {}): Promise<RawWs> {
  return new Promise((res, rej) => {
    const key = crypto.randomBytes(16).toString('base64');
    const s = net.connect(port, HOST);
    let buf = Buffer.alloc(0); let opened = false;
    const frames: Frame[] = []; const waiters: ((f: Frame | null) => void)[] = [];
    const api: RawWs = {
      s, status: 0, head: '', acceptOk: false,
      send(op, payload, { fin = true, mask = true, rsv = 0 } = {}) {
        const body0 = Buffer.from(payload as Buffer);
        const len = body0.length;
        const hdr = [((fin ? 0x80 : 0) | rsv | op)];
        if (len < 126) hdr.push((mask ? 0x80 : 0) | len);
        else if (len < 65536) hdr.push((mask ? 0x80 : 0) | 126, len >> 8, len & 255);
        else { hdr.push((mask ? 0x80 : 0) | 127); const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(len)); hdr.push(...b); }
        let body = body0;
        if (mask) { const m = crypto.randomBytes(4); hdr.push(...m); body = Buffer.from(body0.map((x, i) => x ^ m[i & 3])); }
        s.write(Buffer.concat([Buffer.from(hdr), body]));
      },
      next(ms = 3000) {
        return new Promise((r) => {
          if (frames.length) return r(frames.shift()!);
          waiters.push(r);
          setTimeout(() => { const i = waiters.indexOf(r); if (i >= 0) { waiters.splice(i, 1); r(null); } }, ms);
        });
      },
      closed: new Promise((r) => s.on('close', r)),
    };
    s.on('connect', () => {
      const h: Record<string, string | null> = { Host: `${HOST}:${port}`, Upgrade: 'websocket', Connection: 'Upgrade', 'Sec-WebSocket-Key': key, 'Sec-WebSocket-Version': '13', ...headers };
      s.write(`GET ${p} HTTP/1.1\r\n` + Object.entries(h).filter(([, v]) => v !== null).map(([k, v]) => `${k}: ${v}`).join('\r\n') + '\r\n\r\n');
    });
    s.on('data', (d) => {
      buf = Buffer.concat([buf, d]);
      if (!opened) {
        const i = buf.indexOf('\r\n\r\n'); if (i < 0) return;
        const head = buf.subarray(0, i).toString(); buf = buf.subarray(i + 4);
        api.status = +head.split(' ')[1]; api.head = head; opened = true;
        const want = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
        api.acceptOk = head.toLowerCase().includes('sec-websocket-accept: ' + want.toLowerCase());
        res(api);
      }
      while (buf.length >= 2) {
        let len = buf[1] & 127, pos = 2;
        if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); pos = 4; }
        else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); pos = 10; }
        if (buf.length < pos + len) return;
        const f: Frame = { op: buf[0] & 15, fin: !!(buf[0] & 128), masked: !!(buf[1] & 128), payload: buf.subarray(pos, pos + len) };
        if (f.op === 8) f.code = len >= 2 ? f.payload.readUInt16BE(0) : null;
        buf = buf.subarray(pos + len);
        const w = waiters.shift(); if (w) w(f); else frames.push(f);
      }
    });
    s.on('error', (e) => { if (!opened) rej(e); });
    setTimeout(() => { if (!opened) rej(new Error('handshake timeout')); }, 5000);
  });
}
