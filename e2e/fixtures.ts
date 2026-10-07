import { test as base, expect } from '@playwright/test';
import { startServer, stopServer, type Server } from './helpers/server';

// One server per worker, each with its own in-memory store — that's what lets the
// suite run fully in parallel. The binary is built once in global-setup.ts; here
// we only start it (on a port the OS picks, see helpers/server.ts).
export const test = base.extend<object, { server: Server }>({
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
