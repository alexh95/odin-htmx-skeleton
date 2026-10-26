// ---- the hyperscript client's gate (PLAN §12.4; research 05 §5) -----------------
//
// With hyperscript on a page, an injected `_` attribute or <script
// type="text/hyperscript"> runs: the CSP no longer backstops an escaping mistake.
// So hyperscript initialises an element only when its `_` is a lone
// `install <Name>`: every behaviour lives in behaviours._hs, which is loaded from
// this origin and evaluated directly, not through this check. Markup carries no
// code, and data reaches a behaviour only through data-* attributes.
document.addEventListener("hyperscript:before:init", function (e) {
  var el = e.target;
  var src = el && el.getAttribute ? el.getAttribute("_") : null;
  if (!/^\s*install\s+[A-Z][A-Za-z0-9_]*(\s*\([^)]*\))?\s*$/.test(src || "")) e.preventDefault();
});
