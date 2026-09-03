import { test, expect } from '../fixtures';

// The crawler-facing contract. None of this is visible in the UI, so it can rot
// silently — these are the checks that catch it.
//
// Everything is derived from what the app actually serves rather than hardcoded:
// the canonical origin is a compile-time constant (views.SITE_URL) and the page
// set comes from views.NAV, which `init --minimal` legitimately shrinks. So the
// assertions match on shape and cross-check the app against itself, and the same
// spec holds for the full demo and the minimal starter alike.
const ORIGIN = /^https:\/\/[a-z0-9.-]+$/;

function attr(text: string, re: RegExp): string {
  const m = text.match(re);
  expect(m, `no match for ${re}`).toBeTruthy();
  return m![1];
}

async function sitemapPaths(request: any): Promise<string[]> {
  const body = await (await request.get('/sitemap.xml')).text();
  return [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => new URL(m[1]).pathname);
}

test.describe('SEO contract', () => {
  test('robots.txt allows the pages and points at the sitemap', async ({ request }) => {
    const res = await request.get('/robots.txt');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('text/plain');
    const body = await res.text();

    expect(body).toContain('User-agent: *');
    expect(body).toContain('Allow: /');

    // Must be absolute, or crawlers ignore the line.
    const sitemap = attr(body, /Sitemap: (\S+)/);
    expect(sitemap).toMatch(/^https:\/\/.+\/sitemap\.xml$/);

    // The demo's fragment routes answer with bare HTML meant to be swapped into a
    // page; indexed alone they are thin near-duplicates competing with the real
    // pages. The minimal starter has none of them, so this is scoped to the demo.
    const paths = await sitemapPaths(request);
    if (paths.includes('/data')) {
      for (const p of ['/ui/', '/api/', '/search', '/contacts', '/validate/', '/forms/submit']) {
        expect(body).toContain(`Disallow: ${p}`);
      }
    }
  });

  test('sitemap.xml lists the nav pages, absolute and on one origin', async ({ request }) => {
    const res = await request.get('/sitemap.xml');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('xml');
    const body = await res.text();

    expect(body.startsWith('<?xml')).toBe(true);
    expect(body).toContain('http://www.sitemaps.org/schemas/sitemap/0.9');

    const locs = [...body.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
    expect(locs.length).toBeGreaterThan(0);
    expect(locs).toContain(`${new URL(locs[0]).origin}/`); // the home page is always in NAV

    const origins = new Set(locs.map((u) => new URL(u).origin));
    expect(origins.size).toBe(1); // a split origin would invalidate the sitemap
    expect([...origins][0]).toMatch(ORIGIN);
  });

  test('every sitemap entry is a real page with a self-referential canonical', async ({ request }) => {
    const paths = await sitemapPaths(request);

    // Cross-checks the two halves against each other: a sitemap entry that 404s,
    // or a page whose canonical points elsewhere, is worse than no sitemap at all.
    for (const path of paths) {
      const res = await request.get(path);
      expect(res.status(), `${path} is listed in the sitemap`).toBe(200);
      const html = await res.text();

      const canonical = attr(html, /<link rel="canonical" href="([^"]+)">/);
      const ogUrl = attr(html, /<meta property="og:url" content="([^"]+)">/);

      expect(canonical).toBe(ogUrl);
      expect(new URL(canonical).pathname, `canonical of ${path}`).toBe(path);
      expect(new URL(canonical).origin).toMatch(ORIGIN);
    }
  });

  test('BingSiteAuth.xml proves ownership with a well-formed token', async ({ request }) => {
    // Deployment-specific, not skeleton functionality: `init` blanks the token and
    // the minimal starter has no route at all, so this is scoped to the demo the
    // same way the robots disallow list is.
    const paths = await sitemapPaths(request);
    test.skip(!paths.includes('/data'), 'no verification token in this variant');

    const res = await request.get('/BingSiteAuth.xml');
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('xml');

    const body = await res.text();
    // Bing parses this as XML; a stray character makes it unverifiable, and the
    // failure surfaces only in Bing's console days later.
    expect(body.startsWith('<?xml')).toBe(true);
    const token = attr(body, /<user>([^<]+)<\/user>/);
    expect(token).toMatch(/^[0-9A-F]{32}$/); // Bing tokens are 32 uppercase hex
  });

  test('the IndexNow key file is served verbatim at its own path', async ({ request }) => {
    // Same deployment-specific scoping as BingSiteAuth: `init` blanks the key and
    // the route is not even registered without one.
    const paths = await sitemapPaths(request);
    test.skip(!paths.includes('/data'), 'no IndexNow key in this variant');

    // Mirrors views.INDEXNOW_KEY. Duplicated on purpose: the path *is* the key, so
    // rotating it must fail here rather than silently deactivate IndexNow.
    const KEY = 'e826b40f813548d2bd2e94885e506dfa';

    const res = await request.get(`/${KEY}.txt`);
    expect(res.status()).toBe(200);
    expect(res.headers()['content-type'] ?? '').toContain('text/plain');
    // The engines compare the body verbatim — a trailing newline or any wrapper
    // fails the ownership check, so this is an exact-equality assertion.
    expect(await res.text()).toBe(KEY);

    // The route pattern escapes the dot; unescaped it would be a Lua wildcard and
    // match any character, handing the key out from near-miss paths.
    expect((await request.get(`/${KEY}Xtxt`)).status()).toBe(404);
  });

  test('social card tags are present and absolute', async ({ request }) => {
    const html = await (await request.get('/')).text();

    expect(attr(html, /<meta name="twitter:card" content="([^"]+)">/)).toBe('summary_large_image');
    expect(attr(html, /<meta property="og:site_name" content="([^"]+)">/).length).toBeGreaterThan(0);
    expect(attr(html, /<meta property="og:title" content="([^"]+)">/).length).toBeGreaterThan(0);

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

  test('JSON-LD parses, names the site and links its repository', async ({ request }) => {
    const html = await (await request.get('/')).text();
    const blocks = [...html.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
    expect(blocks.length).toBeGreaterThan(0);

    // Parsed, not pattern-matched: invalid JSON here is invisible in the UI and
    // fatal to crawlers.
    const ld = blocks.map((m) => JSON.parse(m[1]));
    for (const d of ld) expect(d['@context']).toBe('https://schema.org');

    const code = ld.find((d) => d['@type'] === 'SoftwareSourceCode');
    expect(code, 'a SoftwareSourceCode block').toBeTruthy();
    expect(code.codeRepository).toMatch(/^https:\/\//);
    expect(new URL(code.url).origin).toMatch(ORIGIN);
    expect(code.programmingLanguage).toContain('Odin');

    // Without WebSite.name a search engine derives the site name from the
    // hostname, which on a subdomain is the bare registrable name rather than
    // the project. It must agree with og:site_name to be trusted over that.
    const site = ld.find((d) => d['@type'] === 'WebSite');
    expect(site, 'a WebSite block on the home page').toBeTruthy();
    expect(site.name.length).toBeGreaterThan(0);
    expect(site.name).toBe(attr(html, /<meta property="og:site_name" content="([^"]+)">/));
    expect(new URL(site.url).origin).toMatch(ORIGIN);
  });

  test('WebSite structured data is on the home page only', async ({ request }) => {
    // Google reads it from the home page; repeating it on every page is noise at
    // best and a conflicting site-name signal at worst.
    const paths = (await sitemapPaths(request)).filter((p) => p !== '/');
    for (const path of paths) {
      expect((await (await request.get(path)).text()), path).not.toContain('"WebSite"');
    }
  });

  test('the home page title names the project, not a nav item', async ({ request }) => {
    const home = attr(await (await request.get('/')).text(), /<title>([^<]*)<\/title>/);
    // "Dashboard · Brand" is what a search result would otherwise show for the
    // site as a whole — the nav item, not the product.
    expect(home).not.toMatch(/^Dashboard/);
    expect(home.length).toBeGreaterThan(10);

    // Interior pages keep the "<page> · <brand>" shape.
    const paths = (await sitemapPaths(request)).filter((p) => p !== '/');
    if (paths.length) {
      const inner = attr(await (await request.get(paths[0])).text(), /<title>([^<]*)<\/title>/);
      expect(inner).toContain(' · ');
    }
  });

  test('favicon.ico is served from the site root for search engines', async ({ request }) => {
    // Crawlers look here by default, and are far more reliable with a raster .ico
    // than an SVG — a favicon they cannot use is why a result shows a placeholder.
    const res = await request.get('/favicon.ico');
    expect(res.status()).toBe(200);
    const body = await res.body();
    // ICO magic: reserved=0, type=1 (icon).
    expect([...body.subarray(0, 4)]).toEqual([0x00, 0x00, 0x01, 0x00]);
    expect(body.length).toBeGreaterThan(1000);

    // Both icon links are offered; browsers take the SVG, crawlers the .ico.
    const html = await (await request.get('/')).text();
    expect(html).toContain('href="/favicon.ico"');
    expect(html).toContain('href="/static/favicon.svg"');
  });

  test.describe('canonical host redirect', () => {
    test('a *.fly.dev request is 301d to the canonical origin, query intact', async ({ request }) => {
      const res = await request.get('/?q=ada&sort=name', {
        headers: { Host: 'example-app.fly.dev' },
        maxRedirects: 0,
      });
      expect(res.status()).toBe(301);
      const loc = res.headers()['location'];
      expect(new URL(loc).pathname).toBe('/');
      expect(new URL(loc).search).toBe('?q=ada&sort=name');
      expect(new URL(loc).origin).toMatch(ORIGIN);
    });

    test('/healthz is exempt — the platform probe must not be redirected', async ({ request }) => {
      // A probe that follows a redirect off-host fails the deploy, not the request.
      const res = await request.get('/healthz', {
        headers: { Host: 'example-app.fly.dev' },
        maxRedirects: 0,
      });
      expect(res.status()).toBe(200);
    });

    test('a non-fly host is served normally (localhost dev must keep working)', async ({ request }) => {
      const res = await request.get('/', { maxRedirects: 0 });
      expect(res.status()).toBe(200);
    });
  });
});
