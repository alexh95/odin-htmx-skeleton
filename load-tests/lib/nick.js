import http from 'k6/http';
import { BASE } from './config.js';

// A nick build's member (PLAN §17.1): a nickname picked at /login, kept in the VU's
// cookie jar. k6 is loopback, which run.sh's server counts as the LAN.

export const FORM = { 'Content-Type': 'application/x-www-form-urlencoded' };

export function signIn(name) {
  return http.post(`${BASE}/login`, { nick: name, next: '/' }, { headers: FORM, redirects: 0, tags: { name: 'POST /login' } });
}

// The jar's cookies as a Cookie header: a WebSocket's handshake carries no jar of its own.
export function cookieHeader() {
  const jar = http.cookieJar().cookiesForURL(BASE);
  return Object.keys(jar).map((k) => `${k}=${jar[k][0]}`).join('; ');
}
