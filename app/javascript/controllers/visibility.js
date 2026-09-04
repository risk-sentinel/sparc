// #1047 — show/hide, without reading the inline style attribute.
//
// THE BUG THIS EXISTS TO STOP REPEATING.
//
// Several controllers decided which way to toggle with:
//
//     const editing = el.style.display !== "none"
//
// which asks what an element's own `style=` attribute says, not whether it is
// visible. Every one of those panels started life as `style="display: none;"`,
// so it happened to be right — and the #1047 sweep, whose entire job is to move
// those attributes into classes, silently inverted all of them. A hidden panel
// read as visible, so the first click hid it again and revealed the read view.
//
// It shipped twice before it was caught: the doc-meta Edit toggle and the
// control-row inline editor, both on document show pages. Neither was visible
// to the pixel gate, because neither defect exists until someone clicks.
//
// So the rule is: ASK THE BROWSER whether the element is visible, never the
// attribute; and write visibility through the CLASS, clearing any legacy inline
// `display` on the way past. Views still carrying `style="display: none;"` —
// there are several until the sweep reaches them — migrate the first time they
// are used, rather than keeping a value that would outrank the class forever.
//
// This is deliberately NOT a Stimulus controller: `pin_all_from` makes it
// importable as `controllers/visibility`, while `eagerLoadControllersFrom` only
// registers files ending in `_controller.js`, so it is shared code rather than
// behaviour attached to an element.
export const HIDDEN_CLASS = "sparc-d-none"

// Is the element actually rendered? True regardless of how it was hidden —
// inline style, a class, or an ancestor rule.
export function isVisible(el) {
  return !!el && window.getComputedStyle(el).display !== "none"
}

export function setVisible(el, visible) {
  if (!el) return
  el.classList.toggle(HIDDEN_CLASS, !visible)
  el.style.removeProperty("display")
}

// The common case: two elements that swap, e.g. a read view and an edit form.
// Returns whether the FIRST element ends up visible.
export function swapVisible(showEl, hideEl) {
  setVisible(showEl, true)
  setVisible(hideEl, false)
  return true
}
