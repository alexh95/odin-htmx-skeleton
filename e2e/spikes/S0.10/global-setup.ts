import type { FullConfig } from '@playwright/test';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { startServer } from './server';

// Spike S0.10: fetch the pinned inputs as prepare will (one tarball pin for htmx and its 17
// extensions, one file pin for hyperscript), build tools/bundle, run it over the fixture's four
// profiles, then serve the output. S010_CACHE moves the downloads and the bundles (default: the OS
// temp dir); nothing is written inside the repo.

export const PINS = {
  htmxTarball: 'https://registry.npmjs.org/htmx.org/-/htmx.org-4.0.0.tgz',
  htmxTarballSha256: 'f252cb573805081541b9a89bf1cf177aaa56ce73de1bfee02f9c89d5510f174d',
  htmxMinSha256: 'e484d9171a9db30a39c8f16e3d709d4137f3211c659f8e6125816635033d593f', // = app/prepare.sh
  hyperscript: 'https://unpkg.com/hyperscript.org@0.9.94/dist/_hyperscript.min.js',
  hyperscriptSha256: '4f48d7379281c7271f0a3d14907d68f9814280d757c12bf1e99d49a103b9b86a',
};
export const PROFILES = ['minimal', 'streams', 'full', 'lab'] as const;

const sha256 = (b: Buffer) => createHash('sha256').update(b).digest('hex');

async function fetchPinned(url: string, sha: string, file: string): Promise<Buffer> {
  if (existsSync(file) && sha256(readFileSync(file)) === sha) return readFileSync(file);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  const body = Buffer.from(await res.arrayBuffer());
  if (sha256(body) !== sha) throw new Error(`${url}: checksum mismatch, got ${sha256(body)}`);
  writeFileSync(file, body);
  return body;
}

export default async function globalSetup(config: FullConfig) {
  const repo = path.resolve(path.dirname(config.configFile ?? '.'), '..', '..', '..');
  const cache = process.env.S010_CACHE ?? path.join(os.tmpdir(), 's010-bundles');
  mkdirSync(path.join(cache, 'htmx'), { recursive: true });

  const tgz = path.join(cache, 'htmx', 'htmx.org-4.0.0.tgz');
  await fetchPinned(PINS.htmxTarball, PINS.htmxTarballSha256, tgz);
  const dist = path.join(cache, 'htmx', 'package', 'dist');
  execFileSync('tar', ['-xzf', 'htmx.org-4.0.0.tgz'], { cwd: path.join(cache, 'htmx') });
  if (sha256(readFileSync(path.join(dist, 'htmx.min.js'))) !== PINS.htmxMinSha256) throw new Error('htmx.min.js in the tarball is not the pinned file');
  const hyperscript = path.join(cache, '_hyperscript.min.js');
  await fetchPinned(PINS.hyperscript, PINS.hyperscriptSha256, hyperscript);

  const tool = path.join(cache, process.platform === 'win32' ? 'bundle.exe' : 'bundle');
  execFileSync('odin', ['build', 'tools/bundle', `-out:${tool}`, '-vet', '-strict-style', '-warnings-as-errors'], { cwd: repo, stdio: 'inherit' });
  const out = path.join(cache, 'out');
  for (const p of PROFILES) {
    execFileSync(tool, [p, '--repo', 'tools/bundle/fixture', '--htmx', dist, '--out', out], { cwd: repo, stdio: 'inherit' });
  }

  const server = await startServer({ out, htmx: dist, hyperscript });
  process.env.S010_URL = server.url;
  process.env.S010_OUT = out;
  process.env.S010_HTMX = dist;
  process.env.S010_REPO = repo;
  process.env.S010_NAMES = JSON.stringify(server.names);
  return server.close;
}
