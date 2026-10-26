import path from 'node:path';

// Where things are, and which build runs (see server.ts). No Playwright import: global-setup uses it.
export const REPO = path.resolve(__dirname, '..', '..', '..');
export const SPIKE = path.join(REPO, 'docs', 'spikes', 'S0.3');
export const LOCAL_BIN = path.join(SPIKE, 'server', 'bin', process.platform === 'win32' ? 's03.exe' : 's03');
export const HOST = '127.0.0.1';
export const LEG = process.env.S03_LEG === 'wsl' ? 'wsl' : 'local';
