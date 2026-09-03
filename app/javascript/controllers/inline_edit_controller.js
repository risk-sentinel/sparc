import { Controller } from "@hotwired/stimulus"
import { isVisible, setVisible } from "controllers/visibility"

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
//
// #1047 — IT READ THE INLINE STYLE ATTRIBUTE, AND THE SWEEP TOOK THAT AWAY.
//
// The check used to be `edit.style.display !== "none"`, which asks what an
// element's own style= attribute says rather than whether it is visible. The
// edit form started as `style="display: none;"`, so it happened to be right.
// Converting that to `.sparc-edit-panel` left `style.display` empty, `editing`
// read TRUE while the form was hidden, and clicking Edit hid an already-hidden
// form, left the read view up and flipped the button to "Cancel" — the control
// could not be edited at all.
//
// Same defect as doc_meta_controller, same cause, and a screenshot cannot show
// either: both only exist after a click.
//
// So: read COMPUTED display, which is true however the element was hidden, and
// write through the class. The SAR and POA&M show pages still carry the legacy
// `style="display: none;"` until the sweep reaches them, so this has to handle
// both; it clears any inline display it finds, which migrates a row the first
// time it is used rather than leaving a value that would outrank the class.
export default class InlineEditController extends Controller {
  toggle(event) {
    const id = event.params.id

    const details = document.getElementById(`details-${id}`)
    if (details && !details.open) details.open = true

    const view = document.getElementById(`view-${id}`)
    const edit = document.getElementById(`edit-${id}`)
    if (!view || !edit) return

    const editing = isVisible(edit)
    setVisible(view, editing)
    setVisible(edit, !editing)

    const btn = document.getElementById(`edit-btn-${id}`)
    if (btn) {
      btn.textContent = editing ? "Edit" : "Cancel"
      // Assigning element.style from JS is CSSOM, not a `style=` attribute in
      // markup, so `style-src` does not block it.
      btn.style.background = editing ? "#3498db" : "var(--bs-secondary-bg)"
      btn.style.color = editing ? "white" : "var(--bs-secondary-color)"
    }
  }
}
