"""The hide class wins over every class that sets `display` (#1107), in Chrome.

`setVisible(el, false)` hides by adding `.sparc-d-none`. If a class on the
same element sets `display` and wins the cascade, the element stays on screen
with no error. That shipped once: the heat-map filter banner carried `.d-flex`
(Bootstrap's `display: flex !important`) and rendered visible until JavaScript
hid it. PR #1110 made `.sparc-d-none` `display: none !important`.

spec/quality/hide_class_cascade_spec.rb guards the source: the hide rule, no
rival `!important`, load order. This proves the RESULT in a real browser, where
every stylesheet the page actually loads takes part in the cascade.

The class list is read from the page's own stylesheets, so a component class
added later is covered without editing this file. Bootstrap's display
utilities are listed explicitly as well, so the check does not depend on the
CDN sheet's rules being readable from script.
"""

from __future__ import annotations

from helpers import assert_no_csp_violations, record_csp

BOOTSTRAP_DISPLAY = [
    f"d-{v}"
    for v in (
        "inline",
        "inline-block",
        "block",
        "grid",
        "inline-grid",
        "table",
        "table-row",
        "table-cell",
        "flex",
        "inline-flex",
    )
]

# Every single-class rule that sets `display`, from every stylesheet the page
# can read, including rules inside @media blocks.
DISPLAY_CLASSES_JS = """
() => {
  const found = new Set();
  const visit = (rules) => {
    for (const rule of rules) {
      if (rule.cssRules && !rule.selectorText) { visit(rule.cssRules); continue; }
      if (!rule.style || !rule.style.display) continue;
      for (const sel of rule.selectorText.split(",")) {
        const m = sel.trim().match(/^\\.([\\w-]+)$/);
        if (m) found.add(m[1]);
      }
    }
  };
  for (const sheet of document.styleSheets) {
    try { visit(sheet.cssRules); } catch (e) { /* cross-origin sheet */ }
  }
  return [...found];
}
"""

# Put each class on a fresh element next to .sparc-d-none, and report the
# ones that still render.
STILL_VISIBLE_JS = """
(classes) => {
  const host = document.createElement("div");
  document.body.appendChild(host);
  const visible = [];
  for (const cls of classes) {
    const el = document.createElement("div");
    el.className = `sparc-d-none ${cls}`;
    host.appendChild(el);
    const display = getComputedStyle(el).display;
    if (display !== "none") visible.push(`${cls} -> ${display}`);
  }
  host.remove();
  return visible;
}
"""


def test_hide_class_beats_every_display_class(authed_page):
    page = authed_page
    record_csp(page)
    page.goto("/")

    from_sheets = page.evaluate(DISPLAY_CLASSES_JS)
    classes = sorted((set(from_sheets) | set(BOOTSTRAP_DISPLAY)) - {"sparc-d-none"})

    # The class list must actually come from the stylesheet, or the check
    # quietly shrinks to the Bootstrap list.
    assert "sparc-modal-overlay" in from_sheets, (
        f"sparc-theme.css was not read: {len(from_sheets)} classes found"
    )
    assert len(classes) > 50, classes

    still_visible = page.evaluate(STILL_VISIBLE_JS, classes)
    assert still_visible == [], (
        f".sparc-d-none lost the cascade to {len(still_visible)} class(es): {still_visible}"
    )
    assert_no_csp_violations(page)
