import { test, expect } from '../fixtures';
import { startServer, stopServer } from '../helpers/server';

// The *.fly.dev → SITE_URL redirect never fires for a placeholder origin: a
// fork on fly.dev without a domain yet must serve its pages, not bounce every
// visitor to https://<name>.example.com (what init writes). Each case boots its
// own server with its own SITE_URL, so it holds for the demo and the --minimal
// starter alike (seo.spec.ts covers the built-in origin).
const fly = { Host: 'acme-notes.fly.dev' };

async function withServer(env: NodeJS.ProcessEnv, body: (base: string) => Promise<void>) {
  const srv = await startServer(test.info().config, env);
  try {
    await body(`http://127.0.0.1:${srv.port}`);
  } finally {
    await stopServer(srv);
  }
}

test.describe('canonical host redirect', () => {
  test('a real SITE_URL: fly.dev 301s there, query intact', async ({ request }) => {
    await withServer({ SITE_URL: 'https://notes.acme-real.dev' }, async (base) => {
      const res = await request.get(`${base}/about?x=1`, { headers: fly, maxRedirects: 0 });
      expect(res.status()).toBe(301);
      expect(res.headers()['location']).toBe('https://notes.acme-real.dev/about?x=1');

      // The platform probe is exempt, and any other host is served.
      expect((await request.get(`${base}/healthz`, { headers: fly, maxRedirects: 0 })).status()).toBe(200);
      expect((await request.get(`${base}/`, { maxRedirects: 0 })).status()).toBe(200);
    });
  });

  test('a placeholder SITE_URL: fly.dev is served, not sent to example.com', async ({ request }) => {
    await withServer({ SITE_URL: 'https://acme-notes.example.com' }, async (base) => {
      const res = await request.get(`${base}/`, { headers: fly, maxRedirects: 0 });
      expect(res.status()).toBe(200);
      // The tags still name it: it's what the fork told the app its origin is.
      expect(await res.text()).toContain('<link rel="canonical" href="https://acme-notes.example.com/">');
    });
  });

  test('any reserved example or test name counts as a placeholder', async ({ request }) => {
    await withServer({ SITE_URL: 'https://shop.test' }, async (base) => {
      expect((await request.get(`${base}/`, { headers: fly, maxRedirects: 0 })).status()).toBe(200);
    });
  });
});
