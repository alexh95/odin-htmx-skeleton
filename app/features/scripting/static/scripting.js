// ---- scripting: the password rules in plain JavaScript (PLAN §12.3) -------------------
//
// /scripting/live builds one widget three ways; this is the app.js way: one
// delegated listener for any [data-pw-rules] card, ticking each <li data-rule>
// with .ok and writing the score. The hyperscript card is the PasswordRules
// behaviour, and the hx-live card is bindings in its markup. Wrapped, as a
// feature's script shares app.js with every other.
(function () {
  var PW_RULES = {
    len: function (v) { return v.length >= 12; },
    digit: function (v) { return /[0-9]/.test(v); },
    mixed: function (v) { return /[a-z]/.test(v) && /[A-Z]/.test(v); },
    word: function (v) { return v !== "" && !/password/i.test(v); }
  };
  document.addEventListener("input", function (e) {
    var card = e.target.closest && e.target.closest("[data-pw-rules]");
    if (!card || e.target.tagName !== "INPUT") return;
    var v = e.target.value, n = 0;
    card.querySelectorAll("li[data-rule]").forEach(function (li) {
      var ok = PW_RULES[li.dataset.rule](v);
      li.classList.toggle("ok", ok);
      if (ok) n++;
    });
    card.querySelector(".scripting-pw-score").textContent = n + " of 4";
  });
})();
