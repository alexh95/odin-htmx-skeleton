import { test as base, expect } from '@playwright/test';
import path from 'node:path';
import { startServer, stopServer, type Server } from './helpers/server';

// The profile under test as its binary describes itself (`--features --json`,
// read once by global-setup.ts): the features it mounts and the member of each
// family it was built with.
type Build = { profile: string; store: string; identity: string; client: string; theme: string; features: string[] };
export const BUILD: Build = JSON.parse(process.env.E2E_FEATURES || '{"features":[]}');

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
      await use();
    },
    { auto: true },
  ],

  // One server per worker, each with its own in-memory store — that's what lets the
  // suite run fully in parallel. The binary is built once in global-setup.ts; here
  // we only start it (on a port the OS picks, see helpers/server.ts).
  server: [
    async ({}, use, workerInfo) => {
      const server = await startServer(workerInfo.config);
      try {
        await use(server);
      } finally {
        await stopServer(server);
      }
    },
    { scope: 'worker' },
  ],

  // Point page + request at this worker's server.
  baseURL: async ({ server }, use) => {
    await use(`http://127.0.0.1:${server.port}`);
  },
});

export { expect };
