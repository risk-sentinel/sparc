import { Controller } from "@hotwired/stimulus"

// #1259 — the role editor's "differs from default" marker and "Reset to
// default" control for a built-in role.
//
// Each field target carries its shipped default in
// data-role-defaults-shipped-value. The marker is shown while the input holds
// something else; Reset puts the shipped default back into the input. Nothing
// is saved until the form is submitted, and the server decides what is
// recorded as the administrator's choice (Role#record_admin_choices): a key
// saved at its shipped default follows the shipped default again.
export default class RoleDefaultsController extends Controller {
  static targets = ["field"]

  connect() {
    this.fieldTargets.forEach((field) => this.refresh(field))
  }

  changed(event) {
    const field = event.target.closest("[data-role-defaults-target~='field']")
    if (field) this.refresh(field)
  }

  reset(event) {
    event.preventDefault()
    const field = event.target.closest("[data-role-defaults-target~='field']")
    if (!field) return

    const input = this.inputOf(field)
    const shipped = field.dataset.roleDefaultsShippedValue
    if (input.type === "checkbox") {
      input.checked = shipped === "true"
    } else {
      input.value = shipped
    }
    input.dispatchEvent(new Event("change", { bubbles: true }))
    this.refresh(field)
  }

  refresh(field) {
    const input = this.inputOf(field)
    const current = input.type === "checkbox" ? String(input.checked) : input.value
    const differs = current !== field.dataset.roleDefaultsShippedValue
    field.querySelectorAll("[data-role-defaults-marker]").forEach((el) => {
      el.hidden = !differs
    })
  }

  inputOf(field) {
    return field.querySelector("[data-role-defaults-input]")
  }
}
