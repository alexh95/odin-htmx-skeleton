import http from 'k6/http';
import { check } from 'k6';
import { BASE } from '../lib/config.js';
import { options as build, summarize } from '../lib/options.js';

// The crawler's view of the site. Cheap by construction — robots.txt is a fixed
// string and sitemap.xml is a walk over views.NAV — so this should sit close to
// the `static` ceiling. It is measured anyway because both are built per request
// rather than served from embedded bytes: if either ever starts touching the
// store, this is the scenario that shows it.
export const options = build();
export const handleSummary = summarize('seo');

export default function () {
  const robots = http.get(`${BASE}/robots.txt`);
  check(robots, {
    'robots 200': (r) => r.status === 200,
    'robots names the sitemap': (r) => r.body.includes('Sitemap:'),
  });

  const sitemap = http.get(`${BASE}/sitemap.xml`);
  check(sitemap, {
    'sitemap 200': (r) => r.status === 200,
    'sitemap lists urls': (r) => r.body.includes('<loc>'),
  });
}
