import { Controller } from "@hotwired/stimulus"

// #947 — narrow the Role select to the roles the chosen attester actually holds
// on this boundary.
//
// The server is the authority: `Attestation` re-checks the pairing on save, so
// this cannot be used to grant anything. It exists so a user is not offered a
// combination that will be rejected — picking a person and then a role they do
// not hold is a round trip that teaches nothing.
//
// The eligible pairs for the CURRENT boundary are embedded as a value, because
// that set is small and already computed to render the attester list. What is
// NOT embedded is a map of the whole estate keyed by boundary: that grows with
// the deployment and publishes more of the roster than this screen needs.
//
// #981 — so when the boundary changes, the set is refetched rather than looked
// up locally. The eligible set is a property of the boundary, and this used to
// be a snapshot of whichever boundary the page was rendered with: pick a
// boundary, then pick `policy_manager` (instance-scoped, valid only for
// instance-wide evidence), and the server correctly refused a pair the form had
// just offered. The server was always right; the form had not been told.
//
// Stimulus rather than an inline handler: the CSP forbids inline `on*=` and
// unnonced <script>, and a form that silently stops working is exactly the
// failure mode this screen already had.
export default class AttesterPickerController extends Controller {
  static targets = ["attester", "role", "status"]

  // { "<user id>": [{ name: "so_iso", label: "System Owner / ISO" }, ...] }
  static values = { eligible: Object, url: String, boundaryId: String }

  connect() {
    this.refresh()
  }

  // #981 — the boundary select changed; ask the server who may attest there.
  //
  // The server stays the sole authority: this only narrows what is OFFERED, and
  // `Attestation#attester_holds_the_attested_role` re-checks the pair on save,
  // so a stale or tampered response cannot widen anything.
  async boundaryChanged(event) {
    const boundaryId = event?.detail?.boundaryId ?? ""
    if (boundaryId === this.boundaryIdValue) return

    this.boundaryIdValue = boundaryId
    if (!this.hasUrlValue) return

    // A later change must win even if an earlier request resolves after it —
    // otherwise a quick double-change leaves the picker describing the wrong
    // boundary, which is the bug this method exists to fix.
    const request = Symbol("attester-eligibility")
    this.pendingRequest = request

    this.announce("Loading attesters for this system\u2026")

    try {
      const url = new URL(this.urlValue, window.location.origin)
      if (boundaryId) url.searchParams.set("authorization_boundary_id", boundaryId)

      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const payload = await response.json()
      if (this.pendingRequest !== request) return

      this.replaceAttesters(payload?.data?.attesters || [])
      this.eligibleValue = payload?.data?.roles_by_attester || {}
      this.refresh()
    } catch (error) {
      if (this.pendingRequest !== request) return

      // Say so rather than leave the previous boundary's options standing and
      // looking authoritative. A wrong offer is worse than a visible failure —
      // the save would be refused with a message the user cannot act on.
      this.replaceAttesters([])
      this.eligibleValue = {}
      this.refresh()
      this.announce(
        "Could not load attesters for this system. Reload the page and try again."
      )
    }
  }

  // Rebuild the attester select, keeping the current pick when it survives the
  // boundary change so a user who re-picks the same person is not punished for
  // it. `refresh()` then narrows the roles.
  replaceAttesters(attesters) {
    const selected = this.attesterTarget.value

    this.attesterTarget.innerHTML = ""
    this.addOptionTo(this.attesterTarget, "", "Select attester\u2026")
    attesters.forEach((attester) => {
      this.addOptionTo(this.attesterTarget, String(attester.id), attester.label)
    })

    if (attesters.some((attester) => String(attester.id) === selected)) {
      this.attesterTarget.value = selected
    }
  }

  refresh() {
    const selected = this.roleTarget.value
    const roles = this.rolesForCurrentAttester()

    this.roleTarget.innerHTML = ""

    if (!this.attesterTarget.value) {
      this.addOption("", "Choose an attester first")
      this.roleTarget.disabled = true
      // #981 — after a boundary change there may be nobody at all, which is a
      // different thing from "you have not picked yet" and needs saying.
      this.announce(
        Object.keys(this.eligibleValue || {}).length === 0
          ? "No account holds a role that may attest on this system."
          : ""
      )
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
    this.addOptionTo(this.roleTarget, value, label)
  }

  addOptionTo(select, value, label) {
    const option = document.createElement("option")
    option.value = value
    option.textContent = label
    select.appendChild(option)
  }

  announce(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
  }
}
