// Screencast recorder for real UI footage: drives system Chrome headless via
// Playwright, captures every compositor frame over CDP (Page.startScreencast) at
// a real forced device scale, logs mouse/keys/clicks + network on the same wall
// clock, and assembles a constant-frame-rate video. The cursor is NOT drawn into
// the page: the composition draws it from the logged path (smooth at 60 fps).
import { chromium } from "playwright-core";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";

export const CHROME = "C:/Program Files/Google/Chrome/Application/chrome.exe";
export const BASE = "https://odin-htmx.alexh95.com";

export async function openRecorder({ outDir, viewport = { width: 1120, height: 700 }, dpr = 3, jpegQuality = 92, colorScheme = "dark" }) {
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(path.join(outDir, "frames"), { recursive: true });
  // Screencast frames come out at DIP size under Playwright's DSF *emulation*, so
  // use a real forced DSF instead. Headless new-mode insets the viewport by
  // 22x98 DIP from --window-size; compensate so innerWidth/innerHeight match.
  const browser = await chromium.launch({
    executablePath: CHROME,
    headless: true,
    args: [`--force-device-scale-factor=${dpr}`, `--window-size=${viewport.width + 22},${viewport.height + 98}`,
      "--hide-scrollbars", "--force-color-profile=srgb", "--disable-features=OverlayScrollbar", "--enable-gpu-rasterization", "--ignore-gpu-blocklist"],
  });
  const context = await browser.newContext({ viewport: null, colorScheme, reducedMotion: "no-preference" });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);

  const frames = []; // { file, ts }
  const log = [];    // { t, kind, ... } — t is epoch seconds (same clock as screencast timestamps)
  const mousePath = []; // { t, x, y }
  const net = new Map();
  let n = 0;
  let recording = false;

  cdp.on("Page.screencastFrame", (f) => {
    cdp.send("Page.screencastFrameAck", { sessionId: f.sessionId }).catch(() => {});
    if (!recording) return;
    const file = `f${String(n++).padStart(6, "0")}.jpg`;
    fs.writeFile(path.join(outDir, "frames", file), Buffer.from(f.data, "base64"), () => {});
    frames.push({ file, ts: f.metadata.timestamp });
  });

  await cdp.send("Network.enable", { maxTotalBufferSize: 64 * 1024 * 1024, maxResourceBufferSize: 16 * 1024 * 1024 });
  cdp.on("Network.requestWillBeSent", (e) => {
    net.set(e.requestId, { id: e.requestId, method: e.request.method, url: e.request.url, t0: e.wallTime, type: e.type, postData: e.request.postData,
      hx: !!(e.request.headers["HX-Request"] || e.request.headers["hx-request"]) });
  });
  cdp.on("Network.responseReceived", (e) => {
    const r = net.get(e.requestId); if (!r) return;
    const h = e.response.headers;
    r.status = e.response.status; r.mime = e.response.mimeType; r.encoding = h["content-encoding"] || h["Content-Encoding"];
    r.protocol = e.response.protocol; r.tResp = Date.now() / 1000;
  });
  cdp.on("Network.loadingFinished", async (e) => {
    const r = net.get(e.requestId); if (!r) return;
    r.encodedDataLength = e.encodedDataLength; r.tDone = Date.now() / 1000;
    if (["Document", "XHR", "Fetch"].includes(r.type)) {
      try {
        const b = await cdp.send("Network.getResponseBody", { requestId: e.requestId });
        const buf = b.base64Encoded ? Buffer.from(b.body, "base64") : Buffer.from(b.body, "utf8");
        r.bodyBytes = buf.length; r.bodyHead = buf.toString("utf8").slice(0, 400);
      } catch (err) { r.bodyErr = String(err.message || err); }
    }
  });

  const now = () => Date.now() / 1000;
  const mark = (kind, data = {}) => { const e = { t: now(), kind, ...data }; log.push(e); return e; };

  let mouse = { x: viewport.width * 0.62, y: viewport.height * 0.78 };
  const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);
  const moveRaw = async (x, y) => { await page.mouse.move(x, y); mousePath.push({ t: now(), x: +x.toFixed(2), y: +y.toFixed(2) }); };

  const api = {
    page, cdp, context, browser, mark, frames, log, mousePath,
    async start() {
      await cdp.send("Page.startScreencast", { format: "jpeg", quality: jpegQuality, everyNthFrame: 1,
        maxWidth: Math.round(viewport.width * dpr), maxHeight: Math.round(viewport.height * dpr) });
      recording = true; mark("start");
    },
    async stop() { mark("stop"); recording = false; await cdp.send("Page.stopScreencast").catch(() => {}); },
    async wait(ms) { await page.waitForTimeout(ms); },
    async waitUntil(epochSec) { const d = epochSec - now(); if (d > 0) await page.waitForTimeout(Math.round(d * 1000)); },
    // Place the cursor without animation (e.g. before recording starts).
    async place(x, y) { mouse = { x, y }; await moveRaw(x, y); mark("place", { x, y }); },
    // Eased, slightly arced cursor travel at ~60 steps/s.
    async moveTo(x, y, ms = 650) {
      const from = { ...mouse }; const steps = Math.max(8, Math.round(ms / 16));
      const dx = x - from.x, dy = y - from.y; const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len, ny = dx / len; const arc = Math.min(36, len * 0.07);
      mark("move", { from, to: { x, y }, ms });
      const t0 = now();
      for (let i = 1; i <= steps; i++) {
        const p = ease(i / steps); const bow = Math.sin(Math.PI * p) * arc;
        await moveRaw(from.x + dx * p + nx * bow, from.y + dy * p + ny * bow);
        const target = t0 + (ms / 1000) * (i / steps);
        const d = target - now(); if (d > 0.001) await page.waitForTimeout(Math.round(d * 1000));
      }
      mouse = { x, y };
    },
    async box(sel) { const b = await page.locator(sel).first().boundingBox(); if (!b) throw new Error("no box for " + sel); return b; },
    async moveToSel(sel, ms = 650, { dx = 0.5, dy = 0.5 } = {}) {
      const b = await api.box(sel);
      await api.moveTo(b.x + b.width * dx, b.y + b.height * dy, ms);
      return b;
    },
    async click({ hold = 80, label = "" } = {}) {
      mark("down", { x: mouse.x, y: mouse.y, label });
      await page.mouse.down(); await page.waitForTimeout(hold); await page.mouse.up();
      mark("up", { x: mouse.x, y: mouse.y, label });
    },
    async typeText(text, { base = 95, jitter = 40, seed = 7, label = "" } = {}) {
      let s = seed; const rnd = () => ((s = (s * 16807) % 2147483647) / 2147483647);
      for (const ch of text) {
        mark("key", { ch, label });
        await page.keyboard.type(ch);
        await page.waitForTimeout(Math.round(base + (rnd() - 0.5) * 2 * jitter));
      }
    },
    async finish(meta = {}) {
      await page.waitForTimeout(300); // let pending getResponseBody calls land
      const out = { viewport, dpr, frames, log, mouse: mousePath, net: [...net.values()], meta };
      fs.writeFileSync(path.join(outDir, "capture.json"), JSON.stringify(out, null, 2));
      await browser.close();
      return out;
    },
  };
  return api;
}

// Build a constant-frame-rate video from screencast frames: each frame is held
// until the next frame's timestamp; the last frame is held until the stop mark.
export function assemble(outDir, { fps = 60, crf = 12, out = "clip.mp4", startTs, endTs, scale } = {}) {
  // Clip time t == capture time (start + t): the first frame is held from `start`,
  // each frame until the next one's timestamp, the last until `end`; -t trims the
  // concat demuxer's repeated-last-entry tail.
  const cap = JSON.parse(fs.readFileSync(path.join(outDir, "capture.json"), "utf8"));
  const start = startTs ?? cap.log.find((e) => e.kind === "start").t;
  const end = endTs ?? cap.log.find((e) => e.kind === "stop").t;
  const fr = cap.frames.filter((f) => f.ts <= end).sort((a, b) => a.ts - b.ts);
  const lines = ["ffconcat version 1.0"];
  let firstIdx = 0;
  for (let i = 0; i < fr.length; i++) if (fr[i].ts <= start) firstIdx = i;
  const used = fr.slice(firstIdx);
  for (let i = 0; i < used.length; i++) {
    const t0 = i === 0 ? start : Math.max(start, used[i].ts);
    const t1 = i + 1 < used.length ? Math.max(start, used[i + 1].ts) : end;
    lines.push(`file 'frames/${used[i].file}'`, `duration ${Math.max(0, t1 - t0).toFixed(6)}`);
  }
  lines.push(`file 'frames/${used[used.length - 1].file}'`);
  fs.writeFileSync(path.join(outDir, "frames.ffconcat"), lines.join(String.fromCharCode(10)));
  const vf = [`fps=${fps}`];
  if (scale) vf.push(`scale=${scale}:flags=lanczos`);
  vf.push("format=yuv420p");
  execFileSync("ffmpeg", ["-y", "-v", "error", "-f", "concat", "-safe", "0", "-i", "frames.ffconcat",
    "-vf", vf.join(","), "-t", (end - start).toFixed(4), "-c:v", "libx264", "-preset", "slow", "-crf", String(crf),
    "-movflags", "+faststart", out], { cwd: outDir, stdio: "inherit" });
  return { start, end, frames: used.length, duration: end - start };
}
