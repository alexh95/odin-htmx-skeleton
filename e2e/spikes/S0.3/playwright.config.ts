import { defineConfig, devices } from '@playwright/test';

// Spike S0.3: 03's 29 contract checks and the stream extensions in real browsers, against the
// spike's `platform/stream` prototype on the fork (docs/spikes/S0.3.md). From e2e/:
//
//   npx playwright test -c spikes/S0.3/playwright.config.ts --project=chromium --project=webkit
//
// One worker: the specs time streams, the reconnect checks wait out backoffs, and the box may be
// shared. Firefox is listed for CI (M2).
export default defineConfig({
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 45_000,
  reporter: [['list']],
  globalSetup: './global-setup.ts',
  outputDir: './test-results', // not e2e/test-results, which the main suite's runs wipe
  use: { trace: 'retain-on-failure' },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
  ],
});
