import { Controller } from "@hotwired/stimulus"

// Expand/collapse all NIST control-family <details> groups on a document show
// page (#647, epic #650). Replaces inline onclick="toggleAllFamilies(true|false)"
// handlers (SSP/SAP/Profile) blocked by strict CSP. The match selector is
// overridable per page via data-family-toggle-selector-value (Profile scopes to
// direct children with "> details").
export default class FamilyToggleController extends Controller {
  static values = {
    selector: { type: String, default: "#controlsContainer details.sparc-family-group" }
  }

  expandAll() { this.#setAll(true) }
  collapseAll() { this.#setAll(false) }

  #setAll(open) {
    document.querySelectorAll(this.selectorValue).forEach((det) => { det.open = open })
  }
}
