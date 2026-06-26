import { defineConfig, devices } from '@playwright/test';

// One shared in-memory store lives in the server process, so the suite runs
// serially against a single fresh binary (rebuilt + relaunched per run by
// serve.mjs). Tests that mutate create uniquely-named rows and clean up.
const PORT = Number(process.env.E2E_PORT ?? 8137);

export default defineConfig({
  testDir: './tests',
  fullyParallel: false,
  workers: 1,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  // The three major engines. workers:1 keeps them serial against the one shared
  // in-memory store, so projects don't race each other.
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
  webServer: {
    command: 'bun serve.mjs',
    env: { E2E_PORT: String(PORT) },
    url: `http://127.0.0.1:${PORT}/healthz`,
    reuseExistingServer: !process.env.CI,
    stdout: 'pipe',
    stderr: 'pipe',
    timeout: 60_000,
  },
});
