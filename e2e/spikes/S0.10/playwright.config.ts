import { defineConfig, devices } from '@playwright/test';

// Spike S0.10: tools/bundle's output and the bundle race (docs/spikes/S0.10.md). From e2e/:
//
//   npx playwright test -c spikes/S0.10/playwright.config.ts --project=files --project=chromium --project=webkit
//
// global-setup builds the bundles from the fixture's EXTS lines and serves them. `files` checks the
// files themselves, with no browser; the engines run bundle-race.spec. Firefox is listed for CI: it
// doesn't start on the dev PC.
export default defineConfig({
  testDir: '.',
  fullyParallel: true,
  retries: 0,
  timeout: 30_000,
  reporter: [['list']],
  globalSetup: './global-setup.ts',
  use: { trace: 'retain-on-failure' },
  projects: [
    { name: 'files', testMatch: /bundle-files\.spec\.ts$/ },
    { name: 'chromium', testMatch: /bundle-race\.spec\.ts$/, use: { ...devices['Desktop Chrome'] } },
    { name: 'webkit', testMatch: /bundle-race\.spec\.ts$/, use: { ...devices['Desktop Safari'] } },
    { name: 'firefox', testMatch: /bundle-race\.spec\.ts$/, use: { ...devices['Desktop Firefox'] } },
  ],
});
