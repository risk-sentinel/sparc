import { Controller } from "@hotwired/stimulus"

// Collapse toggle + per-resource inline edit-row toggle for the shared OSCAL
// back-matter panel (#645, epic #650). Replaces the inline on* handlers and a
// nonce'd <script> global (toggleEditResource) that strict CSP — script-src
// :self, no 'unsafe-inline' — silently blocked, leaving the Edit/Cancel
// buttons inert across every doc type that renders this partial.
export default class OscalBackMatterController extends Controller {
  static targets = ["body", "icon"]

  toggle() {
    this.bodyTarget.classList.toggle("d-none")
    this.iconTarget.textContent =
      this.bodyTarget.classList.contains("d-none") ? "+" : "-"
  }

  // Toggles the hidden edit-row for a given managed resource. The clicked
  // button carries the resource id as a Stimulus action param.
  toggleEdit(event) {
    const id = event.params.resourceId
    const row = this.element.querySelector(`#edit-resource-${id}`)
    if (row) row.classList.toggle("d-none")
  }
}
