// Take 1 — live dashboard paints + counts up, hx-boost to Data & CRUD, open Ada's drawer.
import { openRecorder, assemble, BASE } from "./lib.mjs";

const out = process.argv[2] || "out/take1";
const r = await openRecorder({ outDir: out, dpr: 3 });
await r.page.setContent('<html style="background:#0b0d17;height:100%"><body style="margin:0"></body></html>');
await r.place(1010, 655);
await r.start();
await r.wait(350);
const tNav = r.mark("goto", { url: BASE + "/" }).t;
await r.page.goto(BASE + "/", { waitUntil: "load" });
r.mark("loaded");
await r.page.waitForFunction(() => [...document.querySelectorAll(".stat-value[data-count]")].every((e) => e.dataset.counted && e.textContent === e.dataset.count), null, { timeout: 5000 }).catch(() => {});
r.mark("counted");
await r.waitUntil(tNav + 3.1);
await r.moveToSel('a.nav-link[href="/data"]', 680, { dx: 0.42, dy: 0.55 });
await r.wait(110);
await r.click({ label: "nav-data" });
await r.page.waitForSelector("button.c-open", { timeout: 8000 });
r.mark("data-swapped");
await r.wait(380);
await r.moveToSel("button.c-open >> nth=0", 620, { dx: 0.3, dy: 0.42 });
await r.wait(120);
await r.click({ label: "open-ada" });
await r.page.waitForSelector("aside.drawer-detail", { timeout: 8000 });
r.mark("drawer-in");
await r.wait(1500);
// drift onto the drawer's activity feed, as if reading it
await r.moveTo(905, 330, 900);
await r.wait(1300);
await r.stop();
const cap = await r.finish({ take: "take1" });
const res = assemble(out, { fps: 60, crf: 14, out: "clip.mp4" });
console.log("take1", JSON.stringify({ frames: cap.frames.length, dur: res.duration.toFixed(2) }));
for (const n of cap.net.filter((n) => ["Document", "XHR", "Fetch"].includes(n.type)))
  console.log(n.method, n.url.replace(BASE, ""), n.status, "body", n.bodyBytes, "wire", n.encodedDataLength, n.encoding || "", n.hx ? "hx" : "", (n.tDone - res.start).toFixed(3));
for (const e of cap.log.filter((e) => ["goto", "loaded", "counted", "down", "up", "data-swapped", "drawer-in"].includes(e.kind)))
  console.log(e.kind, e.label || "", (e.t - res.start).toFixed(3));
