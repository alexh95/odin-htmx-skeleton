import { test as base, expect } from '@playwright/test';
import path from 'node:path';
import { hostOf, mainOrigin, portFree, startServer, stopServer, UPSTREAM, type Server } from './helpers/server';

// The profile under test as its binary describes itself (`--features --json`,
// read once by global-setup.ts): the features it mounts and the member of each
// family it was built with.
type Build = { profile: string; store: string; identity: string; client: string; theme: string; features: string[]; hosts?: Record<string, string[]> };
export const BUILD: Build = JSON.parse(process.env.E2E_FEATURES || '{"features":[]}');

// Where the dashboard is: the root, except where `landing` owns it (full's lab host: /dashboard).
export const DASHBOARD = BUILD.features.includes('landing') ? '/dashboard' : '/';

// Whether the build has a feature ("contacts"), or a feature built with one
// family member ("notes-sqlite", "platform-full"). A leading @ is ignored, so a
// spec's tags can be passed as they are.
export function has(tag: string): boolean {
  const name = tag.replace(/^@/, '');
  const dash = name.indexOf('-');
  const feature = dash < 0 ? name : name.slice(0, dash);
  const member = dash < 0 ? '' : name.slice(dash + 1);
  if (!BUILD.features.includes(feature)) return false;
  return member === '' || [BUILD.store, BUILD.identity, BUILD.client, BUILD.theme].includes(member);
}

const TESTS = path.join(__dirname, 'tests');

// E2E_PROXY: the proxy the pages go through (CI's e2e-proxy job), in front of the worker's server on
// E2E_UPSTREAM_PORT (8080, the port the stack Caddyfile forwards to). The server takes the proxy's
// origin as its own and listens beyond loopback, so a proxy in a container reaches it.
// A two-host build's lab host behind it: E2E_PROXY_LAB.
export const PROXY = process.env.E2E_PROXY || '';
const PROXY_LAB = process.env.E2E_PROXY_LAB || '';

// A console line the proxy runs make and apollo doesn't: they serve plain http on a real host name,
// which Chromium calls untrustworthy, so it ignores Cross-Origin-Opener-Policy and says so (behind
// NPM's TLS it applies). Direct runs on 127.0.0.1, a trustworthy origin, never see it.
export const proxyNoise = (text: string) =>
  PROXY !== '' && text.startsWith("The Cross-Origin-Opener-Policy header has been ignored, because the URL's origin was untrustworthy.");

export const test = base.extend<{ selection: void }, { server: Server }>({
  // A spec lives in tests/<f>/ and carries @<f> (or @<f>-<member>), plus a tag
  // for every other feature it touches. It runs when the build has them all and
  // is skipped, naming what's missing, otherwise. An untagged spec fails: it
  // would otherwise run against builds it was never written for.
  selection: [
    async ({}, use, testInfo) => {
      const dir = path.relative(TESTS, testInfo.file).split(path.sep)[0];
      const own = testInfo.tags.some((t) => t === `@${dir}` || t.startsWith(`@${dir}-`));
      if (!own) throw new Error(`a spec in tests/${dir}/ is tagged @${dir}: ${testInfo.titlePath.join(' › ')}`);
      const missing = testInfo.tags.filter((t) => !has(t));
      testInfo.skip(missing.length > 0, `${BUILD.profile} lacks ${missing.join(', ')}`);
      // A two-host build may hold a spec's features on different hosts (home on Houston's, notes on
      // the lab's): no page has them together, so the spec doesn't apply.
      const hosts = Object.values(BUILD.hosts || {});
      const features = testInfo.tags.map((t) => t.replace(/^@/, '').split('-')[0]).filter((f) => f !== 'platform');
      testInfo.skip(hosts.length > 1 && !hosts.some((h) => features.every((f) => h.includes(f))),
        `${BUILD.profile} serves ${features.join(', ')} on different hosts`);
      await use();
    },
    { auto: true },
  ],

  // One server per worker, each with its own in-memory store — that's what lets the
  // suite run fully in parallel. The binary is built once in global-setup.ts; here
  // we only start it (on a port the OS picks, see helpers/server.ts).
  server: [
    async ({}, use, workerInfo) => {
      if (PROXY && !(await portFree(UPSTREAM))) {
        throw new Error(`E2E_UPSTREAM_PORT ${UPSTREAM} is taken: the proxy would reach another server, not this suite's`);
      }
      // Behind a proxy the client the server sees is the proxy's container, not loopback, so on a
      // nick build anyone may take a nickname there, and the proxies' networks count as the LAN
      // (an accounts build's admin pages are LAN-only).
      const server = PROXY
        ? await startServer(workerInfo.config, {
          SITE_URL: new URL(PROXY).origin, BIND_ALL: '1', ACCOUNTS_NICK_FROM: 'all',
          LAN_CIDRS: '127.0.0.0/8,172.16.0.0/12,10.0.0.0/8,192.168.0.0/16',
        }, UPSTREAM)
        : await startServer(workerInfo.config);
      try {
        await use(server);
      } finally {
        await stopServer(server);
      }
    },
    { scope: 'worker' },
  ],

  // Point page + request at this worker's server, or at the proxy in front of it.
  // A spec whose own feature lives only on a two-host build's main host (accounts, audit …) is
  // pointed there; every other at the lab host (helpers/server.ts).
  baseURL: async ({ server }, use, testInfo) => {
    const dir = path.relative(TESTS, testInfo.file).split(path.sep)[0];
    const main = hostOf(dir) === 'main';
    await use(PROXY ? (main ? PROXY : PROXY_LAB || PROXY) : main ? mainOrigin(server.port) : `http://127.0.0.1:${server.port}`);
  },
});

// Every origin the worker's server answers as: a two-host build's main and lab hosts (in that
// order), else the one; behind a proxy, the proxy's. For the specs that hold on every host.
export function origins(server: Server): string[] {
  if (PROXY) return PROXY_LAB ? [PROXY, PROXY_LAB] : [PROXY];
  const lab = `http://127.0.0.1:${server.port}`;
  return Object.keys(BUILD.hosts || {}).length > 1 ? [mainOrigin(server.port), lab] : [lab];
}

export { expect };
