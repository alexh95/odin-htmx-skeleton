// The only client-side script. HTMX drives every interaction; this file just
// covers the few things the server can't: persisting the theme, retiring
// toasts, and a couple of presentation flourishes. No dependencies.

function toggleTheme() {
  var root = document.documentElement;
  var next = root.dataset.theme === "light" ? "dark" : "light";
  root.dataset.theme = next;
  try { localStorage.setItem("theme", next); } catch (e) {}
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
document.body.addEventListener("htmx:load", function (e) { initRanges(e.target); });

// Dismiss the search dropdown on outside-click or Escape; Escape also closes
// any open overlay.
document.addEventListener("click", function (e) {
  var search = document.querySelector(".search");
  var box = document.getElementById("search-results");
  if (search && box && !search.contains(e.target)) box.innerHTML = "";
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
