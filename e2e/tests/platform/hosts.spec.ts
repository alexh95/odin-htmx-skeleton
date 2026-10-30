import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { test, expect } from '../../fixtures';
import { appDirFrom, BIN } from '../../global-setup';
import { mainHost, onMain, get, post, TWO_HOSTS } from '../../helpers/server';
import { ADMIN } from '../../helpers/accounts';

// A two-host build (full: PLAN §7.3, ANSWERS F2): a row answers only on the host whose table
// mounts it and 404s on the other; the lab host runs no identity, so a session cookie sent there
// is a Guest's and nothing sets one. Every literal GET row of `bin --routes --json`, both hosts.
type Route = { host: string; feature: string; id: string; method: string; pattern: string; perm: string; flags: string[] };

test.describe('hosts', { tag: '@platform' }, () => {
  test.skip(!TWO_HOSTS, 'one host');

  test('every GET row answers on its own host and 404s on the other', async ({ server }) => {
    const routes: Route[] = JSON.parse(execFileSync(path.join(appDirFrom(test.info().config), BIN), ['--routes', '--json'], { encoding: 'utf8' }));
    const by = (host: string) => new Set(routes.filter((r) => r.host === host && r.method === 'Get').map((r) => r.pattern));
    const main = by('main');
    const lab = by('lab');
    const lab_host = { host: `127.0.0.1:${server.port}` };
    const checked: string[] = [];
    for (const r of routes) {
      if (r.method !== 'Get' || r.flags.includes('Stream')) continue;
      const p = r.pattern.replace(/%\./g, '.').replace(/%-/g, '-'); // the escaped literals
      if (/[%(\[]/.test(p)) continue; // a pattern with captures has no one URL
      if (p === '/BingSiteAuth.xml') continue; // 404 by design while the brand names no key
      const own = r.host === 'main' ? onMain(server.port) : lab_host;
      const other = r.host === 'main' ? lab_host : onMain(server.port);
      const here = await get(server.port, p, own);
      expect(here.status, `${r.host} ${p}`).not.toBe(404);
      if (!(r.host === 'main' ? lab : main).has(r.pattern)) {
        expect((await get(server.port, p, other)).status, `${p} on the other host`).toBe(404);
      }
      checked.push(`${r.host} ${p}`);
    }
    expect(checked.length).toBeGreaterThan(20);
  });

  test("a session cookie means nothing on the lab host, which sets none", async ({ server }) => {
    const signed = await post(server.port, '/login', `username=${ADMIN.username}&password=${ADMIN.password}`, onMain(server.port));
    expect(signed.status).toBe(303);
    const cookie = String(signed.headers['set-cookie']).split(';')[0];
    const lab = await get(server.port, '/about', { host: `127.0.0.1:${server.port}`, cookie });
    expect(lab.status).toBe(200);
    expect(lab.headers['set-cookie']).toBeUndefined();
    expect(lab.body).not.toContain('data-revoke'); // no member's #live: a Guest's page
    expect((await get(server.port, '/login', { host: `127.0.0.1:${server.port}`, cookie })).status).toBe(404);
    const main = await get(server.port, '/login', { ...onMain(server.port), cookie });
    expect(main.body).toContain(`Signed in as ${ADMIN.username}`);
    expect(mainHost(server.port)).toContain('localhost');
  });
});
