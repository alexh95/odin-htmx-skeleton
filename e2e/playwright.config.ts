import { defineConfig, devices } from '@playwright/test';

// Specs that never open a page: they talk HTTP to a server (their own, or the
// worker's), so a browser engine changes nothing. They run once, as the `api`
// project, instead of once per engine.
const API_ONLY =
  /[\\/](backup|canonical|dashboard|events|ids|limits|ops|persistence|routing|seo|writes)\.spec\.ts$/;

// skeleton runs in the three engines (Firefox in CI only: it can't start on the
// dev PC), every other profile in chromium (PLAN §19.1.2); the api project
// always. E2E_PROFILE picks the profile, as in global-setup.ts.
const ENGINES = (process.env.E2E_PROFILE || 'skeleton') === 'skeleton' ? ['chromium', 'firefox', 'webkit'] : ['chromium'];
const DEVICE: Record<string, string> = { chromium: 'Desktop Chrome', firefox: 'Desktop Firefox', webkit: 'Desktop Safari' };

// global-setup builds the binary once; each worker spawns its own server on its
// own port (see fixtures.ts) with an isolated in-memory store — so the suite
// runs fully in parallel across workers and the three browser engines.
export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // Playwright defaults to ~half the cores; on a small CI runner that's near-
  // serial. Use one worker per core there (CI shards the engines across runners,
  // so each runner handles a single engine). Locally, use the core-based default.
  workers: process.env.CI ? '100%' : undefined,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  globalSetup: './global-setup.ts',
  use: {
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    ...ENGINES.map((name) => ({ name, testIgnore: API_ONLY, use: { ...devices[DEVICE[name]] } })),
    { name: 'api', testMatch: API_ONLY },
  ],
});
