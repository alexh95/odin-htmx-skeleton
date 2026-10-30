import { execFileSync } from 'node:child_process';
import http from 'node:http';
import path from 'node:path';
import { test, expect, BUILD } from '../../fixtures';
import { appDirFrom, BIN } from '../../global-setup';
import { mainHost, startServer, stopServer, TWO_HOSTS, type Server } from '../../helpers/server';
import { ADMIN } from '../../helpers/accounts';

// rbac.spec (PLAN §17.2, §19.1.5; D37, D44): every row of `bin --routes --json` × every role ×
// every host, against the role grants frozen below. A row answers its own host only; on it, a
// role without the row's permission is refused (a guest sent to sign in, a member 403) and a role
// with it gets past the gate; off the LAN a `.Lan_Only` row is not there for anyone.
//
// Nothing a handler does is exercised, so no write lands: a write is sent with a Content-Length
// beyond any row's cap and no body, so a request the gate admits stops at 413 (the gate runs
// before a byte of the body is read; `Connection: close` spares a refusal the unread body's
// drain, which would answer 413 too), and a stream is dropped as soon as its status arrives.

type Route = { host: string; feature: string; id: string; method: string; pattern: string; perm: string; flags: string[] };
type Role = 'Guest' | 'Member' | 'Moderator' | 'Admin';

// Q31's grants, frozen at M4 (authz.ROLE_PERMS): changing who may do what fails here first, and
// is a decision to record (PLAN §22.7), not a refactor. Only the permissions a role adds are listed.
const EVERYONE = ['Bot_Use', 'Video_Watch', 'Wiki_Read'];
const MEMBERS = [...EVERYONE, 'Account_Self', 'Chat_Read', 'Chat_Post', 'Chat_Dm', 'Chat_Create_Room', 'Chat_Attach',
  'Bot_Llama', 'Wiki_Edit', 'Lists_Edit', 'Polls_Create', 'Polls_Vote', 'Calendar_Edit', 'C4_Play'];
const MODS = [...MEMBERS, 'Chat_Moderate', 'Video_Upload', 'Video_Moderate', 'Guestbook_Moderate', 'Term_Watch'];
const GRANTS: Record<Role, string[]> = {
  Guest: EVERYONE,
  Member: MEMBERS,
  Moderator: MODS,
  Admin: [...MODS, 'Term_Write', 'Admin_Accounts', 'Admin_Audit', 'Admin_Ops', 'Admin_Jobs', 'Admin_Modules', 'Admin_Db', 'Admin_Term'],
};

const ACCOUNTS = BUILD.identity === 'accounts';
const ROLES: Role[] = ACCOUNTS ? ['Guest', 'Member', 'Moderator', 'Admin'] : ['Guest'];
const T = { tag: ['@platform'] };

// One URL a row's pattern matches: a capture of digits is an id no row has, anything else a word.
function sample(pattern: string): string {
  return pattern
    .replace(/\(([^)]*)\)/g, (_, inner: string) => (inner.includes('%d') ? '999999' : inner.includes('%x') ? 'abcdef' : 'x'))
    .replace(/%(.)/g, '$1');
}

const lab = (port: number) => `127.0.0.1:${port}`;
const hostFor = (h: string, port: number) => (h === 'main' ? mainHost(port) : lab(port));

// What the gate did, sent with htmx's header so a refusal is a 401 (sign in, step up), not a
// page's 302: `refused` names it ('' = admitted, whatever the handler then answered).
type Probe = { status: number; refused: '' | 'sign-in' | 'step-up' | 'forbidden' };

// `empty`: a write with no body at all, for a host with no row for it, whose front reads (and caps)
// a body before it answers 404.
function probe(port: number, method: string, url: string, host: string, cookie = '', empty = false): Promise<Probe> {
  return new Promise((resolve, reject) => {
    const write = method !== 'GET' && method !== 'HEAD';
    const req = http.request({
      host: '127.0.0.1', port, path: url, method,
      headers: {
        host, connection: 'close', 'hx-request': 'true', ...(cookie ? { cookie } : {}),
        ...(write ? { 'content-type': 'application/x-www-form-urlencoded', 'content-length': empty ? '0' : '1000000000' } : {}),
      },
      agent: false,
    }, (res) => {
      const status = res.statusCode ?? 0;
      const to = String(res.headers['hx-redirect'] ?? '');
      if (status === 401 && to === '/login') return done({ status, refused: 'sign-in' });
      if (status === 401 && to.startsWith('/step-up')) return done({ status, refused: 'step-up' });
      if (status !== 403) return done({ status, refused: '' });
      let b = ''; // front's 403 says so; a handler's own 403 is something else
      res.on('data', (d) => (b += d));
      res.on('end', () => done({ status, refused: b === 'Not allowed.' ? 'forbidden' : '' }));
    });
    const done = (p: Probe) => {
      resolve(p);
      req.destroy();
    };
    req.on('error', (e) => (e.message.includes('socket hang up') || (e as any).code === 'ECONNRESET' ? undefined : reject(e)));
    req.setTimeout(5000, () => req.destroy(new Error(`${method} ${url}: no status`)));
    req.flushHeaders(); // and no body: a write the gate admits stops at the cap
  });
}

function form(port: number, url: string, body: string, headers: http.OutgoingHttpHeaders = {}): Promise<{ status: number; body: string; cookie: string }> {
  return new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1', port, path: url, method: 'POST',
      headers: { host: mainHost(port), 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(body), ...headers },
    }, (res) => {
      let b = '';
      res.on('data', (d) => (b += d));
      res.on('end', () => {
        const sid = (res.headers['set-cookie'] ?? []).map((c) => c.split(';')[0]).find((c) => c.startsWith('sid='));
        resolve({ status: res.statusCode ?? 0, body: b, cookie: sid ?? '' });
      });
    });
    req.on('error', reject);
    req.end(body);
  });
}

async function signIn(port: number, username: string, password: string): Promise<string> {
  const r = await form(port, '/login', new URLSearchParams({ username, password }).toString());
  expect(r.status, `sign-in of ${username}`).toBe(303);
  return r.cookie;
}

// A member of `role`, by an admin's invite: the cookie their sign-up leaves.
async function member(port: number, admin: string, role: Role, username: string): Promise<string> {
  const made = await form(port, '/admin/accounts/invites', new URLSearchParams({ role, uses: '1', days: '1' }).toString(),
    { cookie: admin, 'hx-request': 'true', 'hx-prompt': 'rbac.spec' });
  expect(made.status, `invite for ${role}`).toBe(200);
  const code = /code=([A-Za-z0-9-]+)/.exec(made.body)?.[1] ?? '';
  expect(code, 'the invite link').not.toBe('');
  const password = 'a-long-enough-password';
  const joined = await form(port, '/register', new URLSearchParams({ username, password, again: password, code }).toString());
  expect(joined.status, `${username} joins`).toBe(303);
  return joined.cookie;
}

// A session per role; off the LAN only the admin's (the invites are a LAN-only page).
async function sessions(port: number, lan = true): Promise<Record<Role, string>> {
  const out: Record<Role, string> = { Guest: '', Member: '', Moderator: '', Admin: '' };
  if (!ACCOUNTS) return out;
  out.Admin = await signIn(port, ADMIN.username, ADMIN.password);
  if (!lan) return out;
  out.Member = await member(port, out.Admin, 'Member', 'rbac-member');
  out.Moderator = await member(port, out.Admin, 'Moderator', 'rbac-mod');
  return out;
}

const routes = (): Route[] =>
  JSON.parse(execFileSync(path.join(appDirFrom(test.info().config), BIN), ['--routes', '--json'], { encoding: 'utf8' }));

async function own(env: NodeJS.ProcessEnv, run: (s: Server) => Promise<void>) {
  const s = await startServer(test.info().config, env);
  try {
    await run(s);
  } finally {
    await stopServer(s);
  }
}

test.describe('rbac', T, () => {
  test('every route × every role × every host, against the frozen grants', async () => {
    test.setTimeout(120_000);
    await own({}, async (s) => {
      const all = routes();
      const who = await sessions(s.port);
      const hosts = TWO_HOSTS ? ['main', 'lab'] : ['main'];
      const seen = new Set<string>();
      for (const r of all) {
        const url = sample(r.pattern);
        const method = r.method.toUpperCase();
        for (const role of ROLES) {
          const at = `${role} ${method} ${url} (${r.host})`;
          const got = await probe(s.port, method, url, hostFor(r.host, s.port), who[role]);
          const granted = r.perm === 'Public' || GRANTS[role].includes(r.perm);
          expect(got.refused, at).toBe(granted ? '' : role === 'Guest' ? 'sign-in' : 'forbidden');
        }
        // The other host: nothing there unless its own table has a row for the same path.
        for (const h of hosts) {
          if (h === r.host) continue;
          const theirs = all.some((o) => o.host === h && new RegExp(`^${luaToRe(o.pattern)}$`).test(url));
          if (theirs) continue;
          const got = await probe(s.port, method, url, hostFor(h, s.port), who.Admin, true);
          expect(got.status, `${method} ${url} on the ${h} host`).toBe(404);
        }
        seen.add(r.id + r.host);
      }
      expect(seen.size).toBe(all.length); // 100 % of the rows
    });
  });

  test('off the LAN a Lan_Only row is not there, for an admin too', async () => {
    const lanOnly = routes().filter((r) => r.flags.includes('Lan_Only'));
    test.skip(lanOnly.length === 0, 'no LAN-only rows');
    await own({ LAN_CIDRS: '10.0.0.0/8' }, async (s) => {
      const who = await sessions(s.port, false);
      for (const r of lanOnly) {
        for (const role of ROLES.filter((x) => x === 'Guest' || x === 'Admin')) {
          const got = await probe(s.port, r.method.toUpperCase(), sample(r.pattern), hostFor(r.host, s.port), who[role]);
          expect(got.status, `${role} ${r.id} off the LAN`).toBe(404);
        }
      }
    });
  });
});

// A Lua pattern as a RegExp, for the few classes the route tables use.
function luaToRe(p: string): string {
  return p
    .replace(/%d/g, '\\d').replace(/%x/g, '[0-9a-fA-F]').replace(/%w/g, '[0-9A-Za-z]').replace(/%a/g, '[A-Za-z]')
    .replace(/%([^dxwa])/g, (_, c: string) => '\\' + c);
}
