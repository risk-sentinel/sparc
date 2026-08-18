import { Controller } from "@hotwired/stimulus"

// #947 — narrow the Role select to the roles the chosen attester actually holds
// on this boundary.
//
// The server is the authority: `Attestation` re-checks the pairing on save, so
// this cannot be used to grant anything. It exists so a user is not offered a
// combination that will be rejected — picking a person and then a role they do
// not hold is a round trip that teaches nothing.
//
// The eligible pairs are embedded as a value rather than fetched, because the
// set is small (the attesters for ONE boundary) and already computed to render
// the attester list. A fetch here would be a second source of the same truth.
//
// Stimulus rather than an inline handler: the CSP forbids inline `on*=` and
// unnonced <script>, and a form that silently stops working is exactly the
// failure mode this screen already had.
export default class extends Controller {
  static targets = ["attester", "role", "status"]

  // { "<user id>": [{ name: "so_iso", label: "System Owner / ISO" }, ...] }
  static values = { eligible: Object }

  connect() {
    this.refresh()
  }

  refresh() {
    const selected = this.roleTarget.value
    const roles = this.rolesForCurrentAttester()

    this.roleTarget.innerHTML = ""

    if (!this.attesterTarget.value) {
      this.addOption("", "Choose an attester first")
      this.roleTarget.disabled = true
      this.announce("")
      return
    }

    if (roles.length === 0) {
      this.addOption("", "No attesting role on this boundary")
      this.roleTarget.disabled = true
      this.announce(
        "This person holds no role here that may attest. Add them to the boundary roster with an attesting role first."
      )
      return
    }

    this.roleTarget.disabled = false
    if (roles.length > 1) this.addOption("", "Select role…")
    roles.forEach((role) => this.addOption(role.name, role.label))

    // Keep the prior choice when it is still available, so re-picking the same
    // person does not silently clear a role the user already chose.
    if (roles.some((role) => role.name === selected)) {
      this.roleTarget.value = selected
    } else if (roles.length === 1) {
      this.roleTarget.value = roles[0].name
    }

    this.announce("")
  }

  rolesForCurrentAttester() {
    const id = this.attesterTarget.value
    if (!id) return []
    return this.eligibleValue[id] || []
  }

  addOption(value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    this.roleTarget.appendChild(option)
  }

  announce(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
  }
}
