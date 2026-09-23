// Take 2 — Forms: type an email, server validates it (69 B error → 43 B ok); then the
// real theme picker re-skins the same page on the music's beat grid (0 requests).
import { openRecorder, assemble, BASE } from "./lib.mjs";

const out = process.argv[2] || "out/take2";
const B = 60 / 109.96; // vol-12 beat
const r = await openRecorder({ outDir: out, dpr: 3 });
await r.page.goto(BASE + "/forms", { waitUntil: "load" });
// Warm every style off-camera (style recalc, fonts, raster caches) so the on-camera
// re-skins paint promptly instead of on a cold first render; end back on modern.
for (const st of ["skeuo", "terminal", "brutal", "editorial", "arcade", "modern"]) {
  await r.page.evaluate((x) => pickStyle(x), st);
  await r.wait(300);
}
await r.page.click("details.picker > summary"); await r.wait(400);
await r.page.click("details.picker > summary"); await r.wait(300);
await r.page.fill('input[name="name"]', "Grace Hopper");
const em = await r.box('input[name="email"]');
await r.place(em.x + em.width * 0.62, em.y + 150);
await r.wait(600);
await r.start();
await r.wait(700);
await r.moveTo(em.x + em.width * 0.34, em.y + em.height * 0.55, 480);
await r.wait(90);
await r.click({ label: "focus-email" });
const tFocus = r.log.at(-1).t;
const T0 = tFocus + 5.36; // first re-skin click (mouseup) ↔ 13.11s in the edit

await r.waitUntil(tFocus + 0.2);
await r.typeText("grace@hopper", { base: 88, jitter: 30, seed: 11, label: "email-1" });
await r.page.waitForSelector(".field-msg .msg-err", { timeout: 6000 });
r.mark("msg-err");
await r.waitUntil(tFocus + 2.3);
await r.typeText(".dev", { base: 96, jitter: 22, seed: 5, label: "email-2" });
await r.page.waitForSelector(".field-msg .msg-ok", { timeout: 6000 });
r.mark("msg-ok");
// Tab out of the field: its blur fires `change` → one more validation swap, which
// runs inside a view transition that swallows any click landing during it (app
// bug, filed separately). Letting the keyboard take the blur keeps clicks safe.
await r.waitUntil(tFocus + 3.25);
r.mark("key", { ch: "Tab", label: "tab" });
await r.page.keyboard.press("Tab");

const problems = [];
await r.waitUntil(tFocus + 3.75);
await r.moveToSel("details.picker > summary", 520);
await r.wait(60);
await r.click({ label: "open-picker" });
await r.wait(350); // let the panel's pop animation settle before measuring
if (!(await r.page.evaluate(() => !!document.querySelector("details.picker[open]")))) problems.push("picker did not open");
const seq = ["skeuo", "terminal", "brutal", "editorial", "arcade"];
const pts = {};
for (const st of seq) {
  const bx = await r.box(`[data-pick-style="${st}"]`);
  pts[st] = { x: bx.x + bx.width * 0.45, y: bx.y + bx.height * 0.55 };
}
const hits = await r.page.evaluate((pts) => Object.entries(pts).filter(([s, p]) => { const h = document.elementFromPoint(p.x, p.y); return !(h && h.closest(`[data-pick-style="${s}"]`)); }).map(([s]) => s), pts);
if (hits.length) problems.push("chips not hit-testable: " + hits.join(","));
// Page-side log of each re-skin on the wall clock, read back after the sweep.
await r.page.evaluate(() => { window.__styleLog = []; new MutationObserver(() => window.__styleLog.push([document.documentElement.dataset.style, (performance.timeOrigin + performance.now()) / 1000])).observe(document.documentElement, { attributes: true, attributeFilter: ["data-style"] }); });
for (let i = 0; i < seq.length; i++) {
  await r.moveTo(pts[seq[i]].x, pts[seq[i]].y, i === 0 ? 380 : 200);
  await r.waitUntil(T0 + i * B - 0.06);
  r.mark("down", { x: pts[seq[i]].x, y: pts[seq[i]].y, label: "style-" + seq[i] });
  await r.page.mouse.down();
  await r.waitUntil(T0 + i * B);
  await r.page.mouse.up();
  r.mark("up", { x: pts[seq[i]].x, y: pts[seq[i]].y, label: "style-" + seq[i] });
}
const styleLog = await r.page.evaluate(() => window.__styleLog);
r.mark("styleLog", { entries: styleLog });
const applied = styleLog.map(([st]) => st).join(",");
if (applied !== seq.join(",")) problems.push("re-skins seen: " + applied);
await r.waitUntil(T0 + 4 * B + 0.6);
await r.moveToSel("details.picker > summary", 460);
await r.wait(60);
await r.click({ label: "close-picker" });
await r.wait(250);
if (await r.page.evaluate(() => !!document.querySelector("details.picker[open]"))) problems.push("picker did not close");
await r.moveTo(em.x + em.width * 0.7, em.y + 200, 700);
await r.wait(1200);
await r.stop();

// Backup stills: the same filled form under every style (3x), no recording.
for (const s of ["modern", "skeuo", "terminal", "brutal", "editorial", "arcade"]) {
  await r.page.evaluate((st) => pickStyle(st), s);
  await r.wait(150);
  await r.page.screenshot({ path: `${out}/still-forms-${s}.png` });
}
const cap = await r.finish({ take: "take2", tFocus, T0, beat: B, problems });
console.log(problems.length ? "PROBLEMS: " + problems.join("; ") : "verified: picker opened, 5 styles applied, picker closed");
const res = assemble(out, { fps: 60, crf: 14, out: "clip.mp4" });
console.log("take2", JSON.stringify({ frames: cap.frames.length, dur: res.duration.toFixed(2), tFocus: (tFocus - res.start).toFixed(3), T0: (T0 - res.start).toFixed(3) }));
for (const n of cap.net.filter((n) => ["Document", "XHR", "Fetch"].includes(n.type)))
  console.log(n.method, n.url.replace(BASE, ""), n.status, "body", n.bodyBytes, "wire", n.encodedDataLength, n.hx ? "hx" : "", (n.t0 - res.start).toFixed(3), "→", (n.tDone - res.start).toFixed(3), n.postData || "");
for (const [st, t] of (cap.log.find((e) => e.kind === "styleLog") || { entries: [] }).entries) {
  const nf = cap.frames.find((f) => f.ts > t);
  console.log("re-skin", st, (t - res.start).toFixed(3), "Δbeat", ((t - T0) / B).toFixed(3), "next frame +" + (nf ? ((nf.ts - t) * 1000).toFixed(0) : "?") + "ms");
}
for (const e of cap.log.filter((e) => ["up", "msg-err", "msg-ok"].includes(e.kind)))
  console.log(e.kind, e.label || "", (e.t - res.start).toFixed(3), e.label?.startsWith("style-") ? "Δbeat " + ((e.t - T0) / B).toFixed(3) : "");
