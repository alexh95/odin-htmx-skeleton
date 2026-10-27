// ---- compat: htmx 2's event names, counted (PLAN §12.3) --------------------------------
//
// On /compat/htmx2, htmx-2-compat fires htmx:afterSwap beside htmx 4's
// htmx:after:swap; this counts the old name into #h2-swaps. Elsewhere nothing
// fires it, and the counter isn't there.
(function () {
  document.addEventListener("htmx:afterSwap", function () {
    var out = document.getElementById("h2-swaps");
    if (out) out.textContent = String(Number(out.textContent) + 1);
  });
})();
