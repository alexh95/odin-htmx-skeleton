// The only client-side script. HTMX drives every interaction; this file just
// covers the few things the server can't: the theme picker, retiring toasts,
// and a couple of presentation flourishes. No dependencies.

// Theme picker — two axes on <html>: data-style (treatment) and data-scheme
// (palette). Pure presentation; persisted so the head pre-paint script can
// restore the choice before first paint. No server round-trip.
function persistPref() {
  var r = document.documentElement;
  try {
    localStorage.setItem("style", r.dataset.style || "");
    localStorage.setItem("scheme", r.dataset.scheme || "");
  } catch (e) {}
  markPicker();
}
function pickStyle(name) {
  var r = document.documentElement;
  r.dataset.style = name;
  // Keep the scheme valid for the new style; fall back to its first swatch.
  var swatches = document.querySelectorAll('.picker-schemes[data-for="' + name + '"] [data-pick-scheme]');
  var ids = Array.prototype.map.call(swatches, function (b) { return b.dataset.pickScheme; });
  if (ids.indexOf(r.dataset.scheme) < 0 && swatches[0]) r.dataset.scheme = swatches[0].dataset.pickScheme;
  persistPref();
}
function pickScheme(name) {
  document.documentElement.dataset.scheme = name;
  persistPref();
}
// Set both axes at once — the /components showroom swatches jump straight to a
// given style + scheme.
function setTheme(style, scheme) {
  var r = document.documentElement;
  r.dataset.style = style;
  r.dataset.scheme = scheme;
  persistPref();
}
function markPicker() {
  var r = document.documentElement;
  document.querySelectorAll("[data-pick-style]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.pickStyle === r.dataset.style));
  });
  document.querySelectorAll("[data-pick-scheme]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.pickScheme === r.dataset.scheme));
  });
  document.querySelectorAll(".showroom-swatches .swatch[data-sw-style]").forEach(function (b) {
    b.setAttribute("aria-pressed", String(b.dataset.swStyle === r.dataset.style && b.dataset.swScheme === r.dataset.scheme));
  });
}

// Tabs: the panel content is swapped in by HTMX; we only move the selected
// state across the buttons.
function selectTab(el) {
  var tabs = el.parentElement.querySelectorAll('[role="tab"]');
  for (var i = 0; i < tabs.length; i++) {
    tabs[i].setAttribute("aria-selected", tabs[i] === el ? "true" : "false");
  }
}

function leaveToast(t) {
  t.classList.add("leaving");
  t.addEventListener("animationend", function () { t.remove(); }, { once: true });
}

function dismissToast(btn) {
  var t = btn.closest(".toast");
  if (t) leaveToast(t);
}

// Toasts can arrive from any handler (out-of-band swaps included), so we watch
// the container rather than wiring each source. Each new toast self-retires.
// #toasts is hx-preserve'd (see layout), so a boosted navigation keeps the very
// same node — this one observer, set up once, survives page swaps.
function watchToasts() {
  var host = document.getElementById("toasts");
  if (!host) return;
  new MutationObserver(function (muts) {
    muts.forEach(function (m) {
      m.addedNodes.forEach(function (n) {
        if (n.nodeType === 1 && n.classList.contains("toast")) {
          setTimeout(function () { if (n.isConnected) leaveToast(n); }, 3600);
        }
      });
    });
  }).observe(host, { childList: true });
}

// Count the dashboard stat values up from zero — cheap, and it makes the
// numbers feel alive on first paint.
function countUp() {
  document.querySelectorAll(".stat-value[data-count]").forEach(function (el) {
    if (el.dataset.counted) return; // animate each card once — idempotent so it's
    el.dataset.counted = "1";       // safe to re-run after a boosted nav swap.
    var target = parseInt(el.dataset.count, 10) || 0;
    if (target === 0) return;
    var start = performance.now(), dur = 600;
    function step(now) {
      var t = Math.min(1, (now - start) / dur);
      el.textContent = Math.round(target * (1 - Math.pow(1 - t, 3)));
      if (t < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  });
}

// Range sliders: paint the filled portion to match the value. The fill is a
// background sized by the --fill custom property (see app.css), updated here as
// the thumb moves. Delegated, so it covers sliders swapped in by HTMX too.
function fillRange(el) {
  var min = parseFloat(el.min);
  var max = parseFloat(el.max);
  if (isNaN(min)) min = 0;
  if (isNaN(max)) max = 100;
  var pct = max > min ? ((parseFloat(el.value) - min) / (max - min)) * 100 : 0;
  el.style.setProperty("--fill", pct + "%");
}

function initRanges(root) {
  (root || document).querySelectorAll('input[type="range"]').forEach(fillRange);
}

document.addEventListener("input", function (e) {
  if (e.target.matches && e.target.matches('input[type="range"]')) fillRange(e.target);
});
// htmx 4 fires htmx:after:process when it wires up new content (initial load and
// every swap, boosted navigation included). Re-fill range sliders inside it (e.g.
// the detail edit form), and restore the chrome a boosted body-swap re-renders:
// the picker's pressed state and the dashboard count-up. Both are idempotent, so
// small in-page fragment swaps are cheap no-ops.
document.addEventListener("htmx:after:process", function (e) {
  initRanges(e.target);
  markPicker();
  countUp();
}, true);

// Auto-reset a form marked [data-reset-on-success] after its OWN successful
// submit. Done here (not hx-on) so it works whether the form's target sits inside
// it (#form-result) or elsewhere (#contact-tbody → the table), and so a child
// field's validation request can't trip it: ctx.sourceElement scopes the reset to
// the submitting form. (That child-event leak was a real regression — the email
// field on /forms validates as you type.)
document.addEventListener("htmx:after:request", function (e) {
  var ctx = e.detail && e.detail.ctx;
  if (!ctx || !ctx.response || ctx.response.status >= 400) return;
  var el = ctx.sourceElement;
  if (el && el.matches && el.matches("form[data-reset-on-success]")) el.reset();
}, true);

// Dismiss the search dropdown on outside-click or Escape; Escape also closes
// any open overlay.
document.addEventListener("click", function (e) {
  var search = document.querySelector(".search");
  var box = document.getElementById("search-results");
  if (search && box && !search.contains(e.target)) box.innerHTML = "";
  var picker = document.querySelector(".picker[open]");
  if (picker && !picker.contains(e.target)) picker.removeAttribute("open");
});

document.addEventListener("keydown", function (e) {
  if (e.key !== "Escape") return;
  var overlay = document.getElementById("overlay");
  if (overlay) overlay.innerHTML = "";
  var box = document.getElementById("search-results");
  if (box) box.innerHTML = "";
});

watchToasts();
countUp();
initRanges();
markPicker();
