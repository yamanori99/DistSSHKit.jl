// Swap the tab icon with the Documenter theme (not OS prefers-color-scheme).
(function () {
  var link = document.getElementById("docs-favicon");
  if (link === null) return;
  var light = link.getAttribute("data-light");
  var dark = link.getAttribute("data-dark");
  function isDark() {
    return /theme--(documenter-dark|catppuccin-mocha|catppuccin-macchiato|catppuccin-frappe)(?:\s|$)/.test(
      document.documentElement.className,
    );
  }
  function apply() {
    var href = isDark() ? dark : light;
    if (!href) return;
    if (link.getAttribute("href") === href) return;
    var next = link.cloneNode(true);
    next.setAttribute("href", href);
    link.parentNode.replaceChild(next, link);
    link = next;
  }
  apply();
  new MutationObserver(apply).observe(document.documentElement, {
    attributes: true,
    attributeFilter: ["class"],
  });
})();
