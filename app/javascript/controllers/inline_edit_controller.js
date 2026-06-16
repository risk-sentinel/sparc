import { Controller } from "@hotwired/stimulus"

// Toggles a control/item row between its read view and inline edit form on
// document show pages (#647, epic #650). Replaces the inline
// onclick="toggleEdit(<id>)" / "toggleItemEdit(<id>)" handlers (SSP/SAR/POAM),
// blocked by strict CSP. The row id is passed as a Stimulus action param
// (data-inline-edit-id-param) rather than interpolated into JS.
//
// Markup contract (ids preserved from the original handlers):
//   #details-<id>  — optional <details> auto-opened when editing starts
//   #view-<id>     — read view (shown when not editing)
//   #edit-<id>     — edit form (shown when editing)
//   #edit-btn-<id> — toggle button (label/colour flips Edit ⇄ Cancel)
export default class extends Controller {
  toggle(event) {
    const id = event.params.id

    const details = document.getElementById(`details-${id}`)
    if (details && !details.open) details.open = true

    const view = document.getElementById(`view-${id}`)
    const edit = document.getElementById(`edit-${id}`)
    if (!view || !edit) return

    const editing = edit.style.display !== "none"
    view.style.display = editing ? "" : "none"
    edit.style.display = editing ? "none" : ""

    const btn = document.getElementById(`edit-btn-${id}`)
    if (btn) {
      btn.textContent = editing ? "Edit" : "Cancel"
      btn.style.background = editing ? "#3498db" : "var(--bs-secondary-bg)"
      btn.style.color = editing ? "white" : "var(--bs-secondary-color)"
    }
  }
}
