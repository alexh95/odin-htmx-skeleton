import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, existsSync } from 'node:fs';
import http from 'node:http';
import type { AddressInfo } from 'node:net';
import path from 'node:path';
import type { Duplex } from 'node:stream';
import zlib from 'node:zlib';

// Spike S0.10's test server: it serves tools/bundle's output the way D19 says the binary will (crc32
// names, br > gzip > identity by Accept-Encoding, Vary, one ETag per encoding), plus the three
// stream endpoints the race needs (SSE, WebSocket, multipart) and an echo for hs-include. It stands
// in for the Odin server, whose stream routes are S0.3's and M2's work.

export type Layout = 'main' | 'main-hs' | 'scripting-hs' | 'separate';

export interface Paths {
  out: string; // tools/bundle --out: <out>/<profile>/<bundle>.js[.br|.gz]
  htmx: string; // the pinned htmx 4.0.0 dist/: htmx.min.js, ext/
  hyperscript: string; // _hyperscript.min.js 0.9.94
}

const PREPAINT = "document.documentElement.dataset.prepaint='1'";
const PREPAINT_HASH = createHash('sha256').update(PREPAINT).digest('base64');
const CSP_TAIL = "img-src 'self' data:; object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
// The skeleton's hash CSP (PLAN §12.2) and the `.Nonce_Csp` class for /scripting/*.
const hashCsp = () => `default-src 'self'; script-src 'self' 'sha256-${PREPAINT_HASH}'; style-src 'self'; style-src-attr 'unsafe-inline'; ${CSP_TAIL}`;
const nonceCsp = (n: string) => `default-src 'self'; script-src 'nonce-${n}' 'sha256-${PREPAINT_HASH}'; style-src 'self'; style-src-attr 'unsafe-inline'; ${CSP_TAIL}`;

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const crc = (b: Buffer) => zlib.crc32(b).toString(16).padStart(8, '0');

// The registration names in a bundle's `/* exts: … */` header, as the htmx-config allowlist wants them.
export function headerNames(js: Buffer): string[] {
  const m = /^\/\* exts: (.*) \*\/\n/.exec(js.subarray(0, 512).toString('latin1'));
  return m ? m[1].split(', ') : [];
}

interface Asset {
  identity: Buffer;
  br?: Buffer;
  gz?: Buffer;
  tag: string;
}

function asset(file: string): Asset {
  const identity = readFileSync(file);
  const opt = (ext: string) => (existsSync(file + ext) ? readFileSync(file + ext) : undefined);
  return { identity, br: opt('.br'), gz: opt('.gz'), tag: crc(identity) };
}

export function startServer(p: Paths): Promise<{ url: string; names: Record<string, string>; close: () => Promise<void> }> {
  const main = asset(path.join(p.out, 'full', 'main.js'));
  const scripting = asset(path.join(p.out, 'full', 'scripting.js'));
  const hs = asset(p.hyperscript);
  const mainNames = headerNames(main.identity);
  // Main keeps htmx's own name, so `minimal`'s URL is the skeleton's (D19).
  const names = {
    main: `htmx.${main.tag}.min.js`,
    scripting: `scripting.${scripting.tag}.js`,
    hyperscript: `_hyperscript.${hs.tag}.min.js`,
  };
  const assets: Record<string, Asset> = { [names.main]: main, [names.scripting]: scripting, [names.hyperscript]: hs };
  // The control: htmx and the same extensions as separate deferred files, the layout D19 rejects.
  const EXT_FILE: Record<string, string> = {
    sse: 'hx-sse', ws: 'hx-ws', 'hx-multipart': 'hx-multipart', 'hx-live': 'hx-live', 'hx-pending': 'hx-pending',
    'browser-indicator': 'hx-browser-indicator', 'hx-prompt': 'hx-prompt', preload: 'hx-preload', ptag: 'hx-ptag',
    'history-cache': 'hx-history-cache', 'hx-head': 'hx-head', upsert: 'hx-upsert', 'hx-targets': 'hx-targets',
    download: 'hx-download', compat: 'htmx-2-compat', 'alpine-compat': 'hx-alpine-compat', 'hx-csp': 'hx-csp',
  };
  const separate = ['htmx.min.js', ...mainNames.map((n) => `ext/${EXT_FILE[n]}.min.js`)];

  function page(layout: Layout): { csp: string; html: string } {
    const nonce = randomBytes(16).toString('base64');
    const scriptingPage = layout === 'scripting-hs';
    const withHs = layout === 'main-hs' || scriptingPage;
    const n = scriptingPage ? ` nonce="${nonce}"` : '';
    const hn = scriptingPage ? ` hx-nonce="${nonce}"` : '';
    const exts = scriptingPage ? headerNames(scripting.identity) : mainNames;
    const allow = [...exts, ...(withHs ? ['hs-include'] : [])].join(', ');
    const config = scriptingPage
      ? `{"defaultSwap":"innerHTML","extensions":"${allow}","safeEval":true}`
      : `{"defaultSwap":"innerHTML","extensions":"${allow}"}`;
    const tags =
      layout === 'separate'
        ? separate.map((f) => `<script src="/static/sep/${f}" defer></script>`)
        : [`<script src="/static/${scriptingPage ? names.scripting : names.main}"${n} defer></script>`];
    if (withHs) tags.push(`<script src="/static/${names.hyperscript}"${n} defer></script>`);
    const body = [
      `<div id="ws" hx-ws:connect="/ws/echo" hx-swap="beforeend"${hn}><form id="wsform" hx-ws:send${hn}><input name="msg" value="hi"><button id="wsbtn">send</button></form></div>`,
      `<div id="sse" hx-sse:connect="/sse/one" hx-swap="beforeend"${hn}></div>`,
      `<div id="mp" hx-multipart:connect="/mp/one" hx-swap="beforeend"${hn}></div>`,
      withHs ? `<button id="hs" _="init set :count to 7" hs-include=":count" hx-post="/echo" hx-target="#hsout"${hn}>hs</button><div id="hsout"></div>` : '',
      // hx-csp's gate runs at init: an element without the page nonce loses its hx-* attributes.
      scriptingPage ? `<button id="unnonced" hx-get="/echo" hx-target="#hsout">unnonced</button>` : '',
    ].join('\n');
    const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><title>S0.10 ${layout}</title>
<script>${PREPAINT}</script>
<meta name="htmx-config" content='${config}'>
${tags.join('\n')}</head><body>
${body}
</body></html>`;
    return { csp: scriptingPage ? nonceCsp(nonce) : hashCsp(), html };
  }

  function serveAsset(req: http.IncomingMessage, res: http.ServerResponse, a: Asset) {
    const accepted = String(req.headers['accept-encoding'] ?? '')
      .split(',')
      .map((t) => t.trim().split(/\s*;\s*q=/))
      .filter(([, q]) => q === undefined || Number(q) > 0)
      .map(([name]) => name.toLowerCase());
    const offers = (e: string) => accepted.includes(e);
    const [enc, body] = a.br && offers('br') ? ['br', a.br] : a.gz && offers('gzip') ? ['gzip', a.gz] : ['identity', a.identity];
    const h: http.OutgoingHttpHeaders = {
      'content-type': 'text/javascript; charset=utf-8',
      'cache-control': 'public, max-age=31536000, immutable',
      vary: 'Accept-Encoding',
      etag: `"${a.tag}-${enc}"`,
      'content-length': body.length,
    };
    if (enc !== 'identity') h['content-encoding'] = enc;
    res.writeHead(200, h).end(body);
  }

  const held = new Set<http.ServerResponse>();
  const sockets = new Set<Duplex>();
  const server = http.createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://x');
    const p0 = url.pathname;
    if (p0.startsWith('/page/')) {
      const { csp, html } = page(p0.slice(6) as Layout);
      res.writeHead(200, { 'content-type': 'text/html; charset=utf-8', 'content-security-policy': csp, 'cache-control': 'no-store' }).end(html);
    } else if (p0.startsWith('/static/sep/')) {
      const f = path.join(p.htmx, p0.slice('/static/sep/'.length));
      if (!separate.includes(p0.slice('/static/sep/'.length))) return void res.writeHead(404).end();
      res.writeHead(200, { 'content-type': 'text/javascript; charset=utf-8' }).end(readFileSync(f));
    } else if (p0.startsWith('/static/') && assets[p0.slice(8)]) {
      serveAsset(req, res, assets[p0.slice(8)]);
    } else if (p0 === '/sse/one') {
      // One event, then held open: a closed stream reconnects, and 4.0.0 reports the abort as an
      // unhandled rejection (04 §4.2).
      res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache' });
      res.write(`data: <i id="sse-ok">sse-ok</i>\n\n`);
      held.add(res);
      res.on('close', () => held.delete(res));
    } else if (p0 === '/mp/one') {
      const B = randomBytes(9).toString('hex');
      const part = '<i id="mp-ok">mp-ok</i>';
      res.writeHead(200, { 'content-type': `multipart/mixed; boundary=${B}`, 'cache-control': 'no-cache' });
      res.write(`--${B}\r\nContent-Type: text/html\r\nContent-Length: ${Buffer.byteLength(part)}\r\n\r\n${part}\r\n--${B}`);
      held.add(res);
      res.on('close', () => held.delete(res));
    } else if (p0 === '/echo' && req.method === 'POST') {
      let b = '';
      req.on('data', (c) => (b += c)).on('end', () => {
        res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }).end(`<code id="echoed">${esc(b)}</code>`);
      });
    } else {
      res.writeHead(404).end();
    }
  });

  // A minimal RFC 6455 server for /ws/echo: text frames only, enough for hx-ws.
  server.on('upgrade', (req, socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    if (new URL(req.url ?? '/', 'http://x').pathname !== '/ws/echo') return void socket.destroy();
    const accept = createHash('sha1').update(`${req.headers['sec-websocket-key']}258EAFA5-E914-47DA-95CA-C5AB0DC85B11`).digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    const send = (op: number, payload: Buffer) => {
      const head = payload.length < 126 ? Buffer.from([0x80 | op, payload.length]) : Buffer.from([0x80 | op, 126, payload.length >> 8, payload.length & 255]);
      socket.write(Buffer.concat([head, payload]));
    };
    send(1, Buffer.from('<i id="ws-open">ws-open</i>'));
    let buf = Buffer.alloc(0);
    socket.on('data', (d: Buffer) => {
      buf = Buffer.concat([buf, d]);
      for (;;) {
        if (buf.length < 2) return;
        const op = buf[0] & 15;
        let len = buf[1] & 127;
        let at = 2;
        if (len === 126) [len, at] = [buf.readUInt16BE(2), 4];
        else if (len === 127) [len, at] = [Number(buf.readBigUInt64BE(2)), 10];
        if (buf.length < at + 4 + len) return;
        const mask = buf.subarray(at, at + 4);
        const data = Buffer.from(buf.subarray(at + 4, at + 4 + len).map((b, i) => b ^ mask[i & 3]));
        buf = buf.subarray(at + 4 + len);
        if (op === 8) return void (send(8, Buffer.alloc(0)), socket.end());
        if (op === 9) send(10, data);
        if (op !== 1) continue;
        let msg = '';
        try {
          msg = String(JSON.parse(data.toString('utf8')).msg ?? '');
        } catch {
          msg = data.toString('utf8');
        }
        send(1, Buffer.from(`<p id="ws-echo">${esc(msg)}</p>`));
      }
    });
    socket.on('error', () => socket.destroy());
  });

  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address() as AddressInfo;
      resolve({
        url: `http://127.0.0.1:${port}`,
        names,
        close: () =>
          new Promise<void>((done) => {
            for (const r of held) r.destroy();
            for (const s of sockets) s.destroy();
            server.closeAllConnections();
            server.close(() => done());
          }),
      });
    });
  });
}
