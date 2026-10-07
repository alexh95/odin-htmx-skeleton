import { defineConfig, devices } from '@playwright/test';

// Specs that never open a page: they talk HTTP to a server (their own, or the
// worker's), so a browser engine changes nothing. They run once, as the `api`
// project, instead of once per engine.
const API_ONLY =
  /[\\/](backup|canonical|dashboard|events|ids|limits|ops|persistence|routing|seo|writes)\.spec\.ts$/;

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
    { name: 'chromium', testIgnore: API_ONLY, use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', testIgnore: API_ONLY, use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', testIgnore: API_ONLY, use: { ...devices['Desktop Safari'] } },
    { name: 'api', testMatch: API_ONLY },
  ],
});
