import { Controller } from "@hotwired/stimulus"

// Toggles a document's OSCAL "doc meta" panel between its read view and its
// edit form (#647, epic #650). Replaces the inline onclick="toggleDocMeta()"
// handlers shared across every document show page (SSP/SAR/SAP/POAM/CDEF/
// Profile), which strict CSP (script-src :self, no 'unsafe-inline') silently
// blocked, leaving the Edit/Cancel buttons inert.
export default class extends Controller {
  static targets = ["view", "edit"]

  toggle() {
    if (!this.hasViewTarget || !this.hasEditTarget) return
    const editing = this.editTarget.style.display !== "none"
    this.viewTarget.style.display = editing ? "" : "none"
    this.editTarget.style.display = editing ? "none" : ""
  }
}
