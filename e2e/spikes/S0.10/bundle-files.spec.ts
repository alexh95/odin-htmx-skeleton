import { expect, test } from '@playwright/test';
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import zlib from 'node:zlib';
import { PINS } from './global-setup';

// tools/bundle's output, checked against an oracle written independently of the tool: the
// extension sets the fixture's EXTS lines should produce, in load order (hx-csp first, then
// platform/ext's enum order), and the concatenation rebuilt here from the pinned files.

const out = () => process.env.S010_OUT!;
const dist = () => process.env.S010_HTMX!;
const sha256 = (b: Buffer) => createHash('sha256').update(b).digest('hex');
const crcName = (b: Buffer) => `htmx.${zlib.crc32(b).toString(16).padStart(8, '0')}.min.js`;

const FILE: Record<string, string> = {
  sse: 'hx-sse', ws: 'hx-ws', 'hx-multipart': 'hx-multipart', 'hx-live': 'hx-live', 'hx-pending': 'hx-pending',
  'browser-indicator': 'hx-browser-indicator', 'hx-prompt': 'hx-prompt', preload: 'hx-preload', ptag: 'hx-ptag',
  'history-cache': 'hx-history-cache', 'hx-head': 'hx-head', upsert: 'hx-upsert', 'hx-targets': 'hx-targets',
  download: 'hx-download', compat: 'htmx-2-compat', 'alpine-compat': 'hx-alpine-compat', 'hx-csp': 'hx-csp',
};

const SCRIPTING = ['hx-csp', 'sse', 'ws', 'hx-multipart', 'hx-live', 'hx-pending'];
const PAGES = { 'scripting.js': SCRIPTING, 'compat_htmx2.js': ['compat'], 'compat_alpine.js': ['alpine-compat'] };
const EXPECTED: Record<string, Record<string, string[]>> = {
  minimal: { 'main.js': [] },
  streams: { 'main.js': ['sse', 'ws', 'hx-multipart', 'hx-pending', 'browser-indicator', 'hx-prompt', 'ptag', 'upsert', 'hx-targets', 'download'] },
  full: {
    'main.js': ['sse', 'ws', 'hx-multipart', 'hx-pending', 'browser-indicator', 'hx-prompt', 'preload', 'ptag', 'history-cache', 'hx-head', 'upsert', 'hx-targets', 'download'],
    ...PAGES,
  },
  lab: { 'main.js': ['sse', 'ws', 'hx-multipart', 'preload', 'history-cache'], ...PAGES },
};

function compose(exts: string[]): Buffer {
  const core = readFileSync(path.join(dist(), 'htmx.min.js'));
  if (exts.length === 0) return core;
  const parts = [Buffer.from(`/* exts: ${exts.join(', ')} */\n`), core];
  for (const e of exts) parts.push(Buffer.from('\n;\n'), readFileSync(path.join(dist(), 'ext', `${FILE[e]}.min.js`)));
  return Buffer.concat(parts);
}

for (const [profile, bundles] of Object.entries(EXPECTED)) {
  test(`${profile}: exactly its bundles, byte for byte, with br and gz that decode to them`, () => {
    const dir = path.join(out(), profile);
    const js = readdirSync(dir).filter((f) => f.endsWith('.js')).sort();
    expect(js).toEqual(Object.keys(bundles).sort());
    for (const [file, exts] of Object.entries(bundles)) {
      const identity = readFileSync(path.join(dir, file));
      expect(identity.equals(compose(exts)), `${profile}/${file} differs from the oracle`).toBe(true);
      // A dev build without brotli or gzip ships fewer encodings (PLAN §12.1); whatever exists must decode.
      const br = path.join(dir, `${file}.br`);
      const gz = path.join(dir, `${file}.gz`);
      if (existsSync(br)) expect(zlib.brotliDecompressSync(readFileSync(br)).equals(identity)).toBe(true);
      if (existsSync(gz)) expect(zlib.gunzipSync(readFileSync(gz)).equals(identity)).toBe(true);
      test.info().annotations.push({
        type: file,
        description: `${identity.length} B, gz ${existsSync(gz) ? readFileSync(gz).length : '-'}, br ${existsSync(br) ? readFileSync(br).length : '-'}`,
      });
    }
  });
}

test("minimal's bundle is the skeleton's htmx.min.js: same SHA-256, same crc32 name", () => {
  const minimal = readFileSync(path.join(out(), 'minimal', 'main.js'));
  expect(sha256(minimal)).toBe(PINS.htmxMinSha256);
  // The skeleton's own copy, when prepare has fetched it.
  const skeleton = path.join(process.env.S010_REPO!, 'app', 'vendor', 'htmx', 'htmx.min.js');
  test.skip(!existsSync(skeleton), 'app/vendor/htmx/htmx.min.js absent: run app/prepare first');
  const sk = readFileSync(skeleton);
  expect(sha256(minimal)).toBe(sha256(sk));
  expect(crcName(minimal)).toBe(crcName(sk));
  test.info().annotations.push({ type: 'name', description: crcName(minimal) });
});

function get(url: string, acceptEncoding?: string): Promise<{ headers: http.IncomingHttpHeaders; body: Buffer }> {
  return new Promise((resolve, reject) => {
    http
      .get(url, { headers: acceptEncoding === undefined ? {} : { 'accept-encoding': acceptEncoding } }, (res) => {
        const chunks: Buffer[] = [];
        res.on('data', (c: Buffer) => chunks.push(c)).on('end', () => resolve({ headers: res.headers, body: Buffer.concat(chunks) }));
      })
      .on('error', reject);
  });
}

test('the server negotiates br > gzip > identity, with Vary and one ETag per encoding', async () => {
  const name = (JSON.parse(process.env.S010_NAMES!) as Record<string, string>).main;
  const url = `${process.env.S010_URL}/static/${name}`;
  const identity = readFileSync(path.join(out(), 'full', 'main.js'));
  const cases: [string | undefined, string | undefined, (b: Buffer) => Buffer][] = [
    ['gzip, deflate, br', 'br', zlib.brotliDecompressSync],
    ['gzip, deflate', 'gzip', zlib.gunzipSync],
    ['br;q=0, gzip', 'gzip', zlib.gunzipSync],
    [undefined, undefined, (b) => b],
  ];
  const etags = new Set<string>();
  for (const [accept, encoding, decode] of cases) {
    const r = await get(url, accept);
    expect(r.headers['content-encoding']).toBe(encoding);
    expect(r.headers.vary).toBe('Accept-Encoding');
    expect(decode(r.body).equals(identity)).toBe(true);
    etags.add(String(r.headers.etag));
  }
  expect(etags.size).toBe(3);
});
