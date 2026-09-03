import { test, expect } from '../fixtures';

// The crawler-facing contract. None of this is visible in the UI, so it can rot
// silently — these are the checks that catch it. The canonical origin is a
// compile-time constant (views.SITE_URL), so the assertions below match on shape
// (absolute, same origin, right path) rather than hardcoding the domain twice.
const ORIGIN = /^https:\/\/[a-z0-9.-]+$/;

async function head(request: any, path: string): Promise<string> {
  const res = await request.get(path);
  expect(res.status()).toBe(200);
  return await res.text();
}

function attr(html: string, re: RegExp): string {
  const m = html.match(re);
  expect(m, `no match for ${re}`).toBeTruthy();
  return m![1];
}

test.describe('SEO contract', () => {
  test('robots.txt allows the pages and disallows the fragment routes', async ({ request }) => {
    const res = await request.get('/robots.txt');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('text/plain');
    const body = await res.text();

    expect(body).toContain('User-agent: *');
    expect(body).toContain('Allow: /');
    // Fragments answer with bare HTML; indexed alone they are thin duplicates.
    for (const p of ['/ui/', '/api/', '/search', '/contacts', '/validate/', '/forms/submit']) {
      expect(body).toContain(`Disallow: ${p}`);
    }
    // The sitemap must be advertised absolutely, or crawlers ignore the line.
    const sitemap = attr(body, /Sitemap: (\S+)/);
    expect(sitemap).toMatch(/^https:\/\/.+\/sitemap\.xml$/);
  });

  test('sitemap.xml lists every nav page, absolute and on one origin', async ({ request }) => {
    const res = await request.get('/sitemap.xml');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('xml');
    const body = await res.text();

    expect(body.startsWith('<?xml')).toBe(true);
    expect(body).toContain('http://www.sitemaps.org/schemas/sitemap/0.9');

    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    // Generated from views.NAV, so this is also the guard against a new page
    // being added to the nav and silently left out of the sitemap.
    expect(locs.length).toBe(5);

    const origins = new Set(locs.map((u) => new URL(u).origin));
    expect(origins.size).toBe(1); // a split origin would invalidate the sitemap
    expect([...origins][0]).toMatch(ORIGIN);

    const paths = locs.map((u) => new URL(u).pathname).sort();
    expect(paths).toEqual(['/', '/about', '/components', '/data', '/forms'].sort());
  });

  test.describe('per-page head tags', () => {
    for (const [path, expected] of [
      ['/', '/'],
      ['/about', '/about'],
      ['/data', '/data'],
    ] as const) {
      test(`canonical + og:url point at ${expected}`, async ({ request }) => {
        const html = await head(request, path);

        const canonical = attr(html, /<link rel="canonical" href="([^"]+)">/);
        const ogUrl = attr(html, /<meta property="og:url" content="([^"]+)">/);

        // Self-referential and absolute: a canonical pointing anywhere else tells
        // Google this page is a copy of that one.
        expect(canonical).toBe(ogUrl);
        expect(new URL(canonical).pathname).toBe(expected);
        expect(new URL(canonical).origin).toMatch(ORIGIN);
      });
    }
  });

  test('social card tags are present and absolute', async ({ request }) => {
    const html = await head(request, '/');

    expect(attr(html, /<meta name="twitter:card" content="([^"]+)">/)).toBe('summary_large_image');
    expect(attr(html, /<meta property="og:site_name" content="([^"]+)">/).length).toBeGreaterThan(0);

    // og:image must be absolute — a relative one is dropped by every scraper.
    const img = attr(html, /<meta property="og:image" content="([^"]+)">/);
    expect(new URL(img).pathname).toBe('/static/og.png');
    expect(new URL(img).origin).toMatch(ORIGIN);
  });

  test('og.png is served from the binary at a stable, unfingerprinted path', async ({ request }) => {
    const res = await request.get('/static/og.png');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('image/png');
    const body = await res.body();
    expect(body.length).toBeGreaterThan(10_000); // a real card, not a stub
    // PNG magic — proves it is an image and not an HTML error page.
    expect([...body.subarray(0, 4)]).toEqual([0x89, 0x50, 0x4e, 0x47]);
  });

  test('JSON-LD parses and links the site to its repository', async ({ request }) => {
    const html = await head(request, '/');
    const raw = attr(html, /<script type="application\/ld\+json">([\s\S]*?)<\/script>/);

    const ld = JSON.parse(raw); // invalid JSON here is invisible in the UI but fatal to crawlers
    expect(ld['@context']).toBe('https://schema.org');
    expect(ld['@type']).toBe('SoftwareSourceCode');
    expect(ld.codeRepository).toMatch(/^https:\/\/github\.com\//);
    expect(new URL(ld.url).origin).toMatch(ORIGIN);
    expect(ld.programmingLanguage).toContain('Odin');
  });

  test.describe('canonical host redirect', () => {
    test('a *.fly.dev request is 301d to the canonical origin, query intact', async ({ request }) => {
      const res = await request.get('/data?q=ada&sort=name', {
        headers: { Host: 'odin-htmx-skeleton.fly.dev' },
        maxRedirects: 0,
      });
      expect(res.status()).toBe(301);
      const loc = res.headers()['location'];
      expect(new URL(loc).pathname).toBe('/data');
      expect(new URL(loc).search).toBe('?q=ada&sort=name');
      expect(new URL(loc).origin).toMatch(ORIGIN);
    });

    test('/healthz is exempt — the platform probe must not be redirected', async ({ request }) => {
      // A probe that follows a redirect off-host fails the deploy, not the request.
      const res = await request.get('/healthz', {
        headers: { Host: 'odin-htmx-skeleton.fly.dev' },
        maxRedirects: 0,
      });
      expect(res.status()).toBe(200);
    });

    test('a non-fly host is served normally (localhost dev must keep working)', async ({ request }) => {
      const res = await request.get('/data', { maxRedirects: 0 });
      expect(res.status()).toBe(200);
    });
  });
});
