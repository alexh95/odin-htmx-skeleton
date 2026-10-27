// ---- the vanilla client's behaviours: the twins of behaviours._hs (D22) ----------
//
// Each element that needs one says `data-behave="<name>"` (html.behave writes it),
// and the delegated listeners below act on it, so swapped-in content needs no
// wiring. The names are platform/html's BEHAVIOURS table's vanilla column.

function behaving(el, name) {
  return el && el.closest ? el.closest('[data-behave="' + name + '"]') : null;
}

// Every element under root (root itself included: htmx fires after:process on
// a swapped element itself) that has behaviour `name`.
function each(root, name, fn) {
  var sel = '[data-behave="' + name + '"]';
  root = root || document;
  if (root.matches && root.matches(sel)) fn(root);
  if (root.querySelectorAll) root.querySelectorAll(sel).forEach(fn);
}

// tabs: a click on a [role=tab] inside the tablist moves aria-selected to it; the
// panel itself is swapped in by htmx.
function selectTab(list, tab) {
  list.querySelectorAll('[role="tab"]').forEach(function (t) {
    t.setAttribute("aria-selected", t === tab ? "true" : "false");
  });
}

// toast: retires itself 3.6 s after it arrives, or when its × is clicked, by
// playing its leave animation first.
function leaveToast(t) {
  if (t.dataset.leaving) return;
  t.dataset.leaving = "1";
  t.classList.add("leaving");
  var gone = function () { t.remove(); };
  t.addEventListener("animationend", gone, { once: true });
  setTimeout(gone, 1000); // reduced motion: no animation, no animationend
}
function armToasts(root) {
  each(root, "toast", function (t) {
    if (t.dataset.armed) return;
    t.dataset.armed = "1";
    setTimeout(function () { if (t.isConnected) leaveToast(t); }, 3600);
  });
}

// range-fill: paints the filled portion of a range input to match its value,
// through the --fill custom property app.css reads, and keeps its label's
// <output> in step.
function fillRange(el) {
  var min = parseFloat(el.min);
  var max = parseFloat(el.max);
  if (isNaN(min)) min = 0;
  if (isNaN(max)) max = 100;
  var pct = max > min ? ((parseFloat(el.value) - min) / (max - min)) * 100 : 0;
  el.style.setProperty("--fill", pct + "%");
}
function initRanges(root) {
  each(root, "range-fill", fillRange);
}

// dismiss: a click outside its parent, or Escape, empties the element (search
// results) or closes it (a <details>).
function dismiss(el) {
  if (el.tagName === "DETAILS") el.removeAttribute("open");
  else el.replaceChildren();
}

document.addEventListener("input", function (e) {
  if (!e.target.matches || !e.target.matches('[data-behave="range-fill"]')) return;
  fillRange(e.target);
  var label = e.target.closest("label");
  var out = label && label.querySelector("output");
  if (out) out.value = e.target.value;
});

document.addEventListener("htmx:after:process", function (e) {
  initRanges(e.target);
  armToasts(e.target);
}, true);

// reset-on-success: a form resets after its OWN successful submit, and empties
// its .form-error slot. ctx.sourceElement scopes it: a child field's validation
// request can't trip it (the /forms email field validates as you type; an
// unscoped reset wiped what the user typed once). A refused submit is a 422, so
// the input stays for the user to fix.
document.addEventListener("htmx:after:request", function (e) {
  var ctx = e.detail && e.detail.ctx;
  if (!ctx || !ctx.response || ctx.response.status >= 400) return;
  var el = ctx.sourceElement;
  if (!el || !el.matches || !el.matches('form[data-behave="reset-on-success"]')) return;
  el.reset();
  el.querySelectorAll(".form-error").forEach(function (m) { m.replaceChildren(); });
}, true);

document.addEventListener("click", function (e) {
  var t = e.target.closest ? e.target : e.target.parentElement;
  var list = behaving(t, "tabs");
  var tab = list && t.closest('[role="tab"]');
  if (tab) selectTab(list, tab);
  var toast = t.closest(".toast-x") && behaving(t, "toast");
  if (toast) leaveToast(toast);
  document.querySelectorAll('[data-behave="dismiss"]').forEach(function (d) {
    if (d.parentElement && !d.parentElement.contains(e.target)) dismiss(d);
  });
});

// search-box: a live search or filter form (htmx fires on keyup) never submits
// and navigates on Enter.
document.addEventListener("submit", function (e) {
  if (e.target.matches('form[data-behave="search-box"]')) e.preventDefault();
});

document.addEventListener("keydown", function (e) {
  if (e.key !== "Escape") return;
  document.querySelectorAll('[data-behave="dismiss"]').forEach(dismiss);
});

armToasts();
initRanges();
