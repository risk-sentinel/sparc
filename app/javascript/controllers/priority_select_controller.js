import { Controller } from "@hotwired/stimulus"

// #1270 — a control's priority, set where it is shown. Saves on change, with
// no Edit, Save or reload, through the same endpoint as the bulk bar
// (ProfileControlBulkEditService), and says whether it saved. On a refusal the
// selector goes back to the value the server still holds.
//
// The control card follows the saved value: its data-priority (which the
// "Not set" chip filters on) and its accent stripe.
const NOT_SET_LABEL = "(None)"

export default class PrioritySelectController extends Controller {
  static targets = ["select", "status"]
  static values = { url: String, controlId: String, accents: Object }

  connect() {
    this.saved = this.selectTarget.value
  }

  async save() {
    const priority = this.selectTarget.value
    this.statusTarget.textContent = "Saving…"
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
        },
        body: JSON.stringify({ control_ids: [this.controlIdValue], priority })
      })
      const body = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(body.error || `Not saved (${response.status})`)

      this.saved = priority
      this.applyToCard(priority)
      this.statusTarget.textContent = "Saved"
    } catch (error) {
      this.selectTarget.value = this.saved
      this.applyToCard(this.saved)
      this.statusTarget.textContent = error.message
    }
  }

  applyToCard(priority) {
    this.selectTarget.classList.toggle("sparc-priority-select--unset", priority === "")
    const card = this.element.closest(".control-card")
    if (!card) return

    card.dataset.priority = priority || NOT_SET_LABEL
    Object.values(this.accentsValue).forEach(cls => card.classList.remove(cls))
    const accent = this.accentsValue[priority] ?? this.accentsValue[""]
    if (accent) card.classList.add(accent)
  }
}
