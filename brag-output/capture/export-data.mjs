// Turn the two captures into composition-time data for the Hyperframes project:
// cursor path, clicks, keystrokes, network responses and visible-change moments.
// comp time = clip time + offset (clip time == capture time − start mark).
import fs from "node:fs";

const OFFSETS = { take1: -0.5, take2: 6.296 };
const round = (v, d = 3) => Math.round(v * 10 ** d) / 10 ** d;

function load(name) {
  const cap = JSON.parse(fs.readFileSync(`out/${name}/capture.json`, "utf8"));
  const start = cap.log.find((e) => e.kind === "start").t;
  const toComp = (t) => round(t - start + OFFSETS[name]);
  const mouse = cap.mouse.filter((m) => m.t >= start - 0.01).map((m) => [toComp(Math.max(m.t, start)), round(m.x, 1), round(m.y, 1)]);
  const downs = cap.log.filter((e) => e.kind === "down").map((e) => ({ t: toComp(e.t), x: round(e.x, 1), y: round(e.y, 1), label: e.label }));
  const ups = cap.log.filter((e) => e.kind === "up").map((e) => ({ t: toComp(e.t), label: e.label }));
  const keys = cap.log.filter((e) => e.kind === "key").map((e) => ({ t: toComp(e.t), ch: e.ch, label: e.label }));
  const net = cap.net
    .filter((n) => ["Document", "XHR", "Fetch"].includes(n.type) && !n.url.includes("/cdn-cgi/") && n.tDone >= start)
    .map((n) => ({ t0: toComp(n.t0), t: toComp(n.tDone), method: n.method, path: n.url.replace(/^https?:\/\/[^/]+/, ""), status: n.status, bytes: n.bodyBytes, head: (n.bodyHead || "").slice(0, 160) }));
  // first captured frame strictly after a capture-time instant → when the change is visible
  const frameAfter = (t) => { const f = cap.frames.find((x) => x.ts > t); return f ? toComp(f.ts) : null; };
  const styleLog = (cap.log.find((e) => e.kind === "styleLog") || { entries: [] }).entries.map(([s, t]) => ({ style: s, t: toComp(t), visible: frameAfter(t) }));
  const marks = Object.fromEntries(cap.log.filter((e) => !["move", "down", "up", "key", "place", "styleLog"].includes(e.kind)).map((e) => [e.kind, toComp(e.t)]));
  const netVisible = net.map((n) => ({ ...n, visible: frameAfter(n.t - OFFSETS[name] + start - (0)) }));
  return { offset: OFFSETS[name], clipDuration: round(cap.log.find((e) => e.kind === "stop").t - start), mouse, downs, ups, keys, net, styleLog, marks, frameAfter, start };
}

const t1 = load("take1");
const t2 = load("take2");
// visible moments measured on captured frames (capture-time → comp-time)
const vis = (take, compT) => take.frameAfter(compT - take.offset + take.start);
const data = {
  take1: { offset: t1.offset, clipDuration: t1.clipDuration, mouse: t1.mouse, downs: t1.downs, ups: t1.ups, net: t1.net, marks: t1.marks },
  take2: { offset: t2.offset, clipDuration: t2.clipDuration, mouse: t2.mouse, downs: t2.downs, ups: t2.ups, keys: t2.keys, net: t2.net, styleLog: t2.styleLog, marks: t2.marks },
  visible: {
    dataPage: vis(t1, t1.net.find((n) => n.path === "/data").t),
    drawer: vis(t1, t1.net.find((n) => n.path === "/contacts/1").t),
    msgErr: vis(t2, t2.net.find((n) => n.bytes === 69).t),
    msgOk: vis(t2, t2.net.find((n) => n.bytes === 43).t),
  },
};
fs.writeFileSync(process.argv[2], "// Generated from the two live-site captures (see ../capture/). Times are composition seconds.\nwindow.CAPTURE = " + JSON.stringify(data) + ";\n");
console.log(JSON.stringify({ visible: data.visible, t1marks: t1.marks, t2marks: t2.marks, t1downs: t1.downs, t2downs: t2.downs.map((d) => [d.label, d.t]), styles: t2.styleLog, net1: t1.net.map((n) => [n.method, n.path, n.bytes, n.t]), net2: t2.net.map((n) => [n.method, n.path, n.bytes, n.t]), mouseN: [t1.mouse.length, t2.mouse.length], keys: t2.keys.map((k) => k.ch + "@" + k.t).join(" ") }, null, 1));
