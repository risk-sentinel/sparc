import { Controller } from "@hotwired/stimulus"
import { setVisible } from "controllers/visibility"

// #1100 — open a statement's editor in place.
//
// Answering a control per part used to cost a full page navigation EACH TIME:
// the Edit control was a link to `?statement_id=N`, which reloaded the whole
// document and rendered a modal at the bottom of it. AC-2 has 22 addressable
// parts, so answering one control meant 22 round trips through a page that
// renders every control on the document.
//
// The controller is scoped to a single <tr>, so targets resolve per row without
// any id-threading between the markup and the JS.
//
// Visibility goes through `controllers/visibility`, never `style.display` —
// `.sparc-d-none` is `display: none !important` and an inline declaration
// cannot outrank it (#1047).
export default class StatementEditController extends Controller {
  static targets = ["read", "form", "prose", "toggle"]

  toggle(event) {
    event.preventDefault()
    this.editing = !this.editing
    this.render()
    if (this.editing && this.hasProseTarget) {
      this.proseTarget.focus()
      // Caret to the end rather than the start, so an author extending an
      // existing answer does not have to travel there first.
      const end = this.proseTarget.value.length
      this.proseTarget.setSelectionRange(end, end)
    }
  }

  cancel(event) {
    event.preventDefault()
    this.editing = false
    this.render()
  }

  render() {
    if (this.hasReadTarget) setVisible(this.readTarget, !this.editing)
    if (this.hasFormTarget) setVisible(this.formTarget, this.editing)
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = this.editing ? "Cancel" : "Edit"
      this.toggleTarget.setAttribute("aria-expanded", this.editing ? "true" : "false")
    }
  }
}
