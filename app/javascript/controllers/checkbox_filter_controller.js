import { Controller } from "@hotwired/stimulus"

// Client-side "contains" filter for a checkbox list. CSP-safe: driven by a
// Stimulus data-action, no inline handlers.
//
// Added for #770 bug 2 — the boundary-environment form's CDEF component picker
// rendered every CDEF as a checkbox with no way to narrow a long list. Filters
// items by their text content (case-insensitive substring) and toggles an
// optional empty-state message.
//
// Usage:
//   <div data-controller="checkbox-filter">
//     <input data-checkbox-filter-target="input"
//            data-action="input->checkbox-filter#filter">
//     <div data-checkbox-filter-target="item">…checkbox + label…</div>
//     <div hidden data-checkbox-filter-target="empty">No matches.</div>
//   </div>
export default class CheckboxFilterController extends Controller {
  static targets = ["input", "item", "empty"]

  filter() {
    const query = this.inputTarget.value.trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const match = query === "" || item.textContent.toLowerCase().includes(query)
      item.hidden = !match
      if (match) visible += 1
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = visible !== 0
  }
}
