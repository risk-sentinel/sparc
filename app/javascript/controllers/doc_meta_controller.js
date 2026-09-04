import { Controller } from "@hotwired/stimulus"
import { isVisible, setVisible } from "controllers/visibility"

// Toggles a document's OSCAL "doc meta" panel between its read view and its
// edit form (#647, epic #650). Replaces the inline onclick="toggleDocMeta()"
// handlers shared across every document show page (SSP/SAR/SAP/POAM/CDEF/
// Profile), which strict CSP (script-src :self, no 'unsafe-inline') silently
// blocked, leaving the Edit/Cancel buttons inert.
//
// #1047 — IT READ THE INLINE STYLE ATTRIBUTE, AND THE SWEEP TOOK THAT AWAY.
//
// The previous check was:
//
//     const editing = this.editTarget.style.display !== "none"
//
// which asks "what does this element's own style= attribute say", not "is this
// element visible". The edit panel started as `style="display: none;"`, so that
// happened to be true. Converting it to `.sparc-d-none` left `style.display`
// empty, `editing` became true when the panel was in fact hidden, and the first
// click HID an already-hidden panel while revealing the view — the Edit button
// inverted on every document show page.
//
// Nothing in a screenshot could show that, which is why it was the ui-smoke
// interaction check that caught it and not the pixel gate.
//
// So: read COMPUTED display, which is true regardless of how the element was
// hidden, and write through the class. Five of the six views still carry the
// legacy `style="display: none;"` while the sweep works through them, so this
// has to handle both — it clears any inline display it finds, which migrates
// each panel the first time it is used.
export default class DocMetaController extends Controller {
  static targets = ["view", "edit"]

  toggle() {
    if (!this.hasViewTarget || !this.hasEditTarget) return

    const editing = isVisible(this.editTarget)
    setVisible(this.viewTarget, editing)
    setVisible(this.editTarget, !editing)
  }
}
