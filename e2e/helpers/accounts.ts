import type { Browser, BrowserContext, Page } from '@playwright/test';

// The accounts identity's test admin (PLAN §17.1): helpers/server.ts boots every accounts
// build with ADMIN_HASH as ACCOUNTS_ADMIN_HASH, so `admin` with ADMIN.password is its first
// admin. Test values only: the hash was made with `bin --hash-password` from this password,
// and load-tests/run.sh boots its servers with the same pair.
export const ADMIN = { username: 'admin', password: 'e2e-and-load-only-password' };
export const ADMIN_HASH = '$argon2id$v=19$m=19456,t=2,p=1$usNdKTDf754mp5KZr0QZOg$UmN+6Cr4ai7YMbp4f0SsrCtA/kmVO/w4cSHz7Fs8F8I';

export type Signed = { context: BrowserContext; page: Page };

// A browser context of its own, signed in through the form, landed on `next`.
export async function signIn(browser: Browser, baseURL: string, next = '/'): Promise<Signed> {
  const context = await browser.newContext({ baseURL });
  const page = await context.newPage();
  await page.goto(`/login?next=${encodeURIComponent(next)}`);
  await page.locator('#username').fill(ADMIN.username);
  await page.locator('#password').fill(ADMIN.password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await page.waitForURL((u) => u.pathname === next);
  return { context, page };
}
