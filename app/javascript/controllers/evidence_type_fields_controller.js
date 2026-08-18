import { Controller } from "@hotwired/stimulus"

// #947 — show the fields the chosen evidence type actually needs.
//
// An attestation IS evidence: its substance is a statement by an accountable
// person, and there may be no file at all. An artefact type is the reverse. So
// the form asks for whichever the type calls for, on one screen, in one save.
//
// This is presentation only. `Evidence` validates both rules server-side
// (`file_required_for_artefact_types`, `attestation_required_for_attestation_types`),
// so a user with scripting disabled sees every field and still gets a correct,
// visible error rather than a silent refusal — which is the failure this issue
// was filed about.
//
// Stimulus rather than an inline handler: the CSP forbids inline `on*=` and
// unnonced <script>.
export default class extends Controller {
  static targets = ["type", "attestation", "fileHint", "artefactHint"]
  static values = { attestationTypes: Array }

  connect() {
    this.refresh()
  }

  refresh() {
    const isAttestation = this.attestationTypesValue.includes(this.typeTarget.value)

    this.attestationTargets.forEach((el) => el.classList.toggle("d-none", !isAttestation))
    this.fileHintTargets.forEach((el) => el.classList.toggle("d-none", !isAttestation))
    this.artefactHintTargets.forEach((el) => el.classList.toggle("d-none", isAttestation))

    // Fields inside a hidden block must not be submitted — an empty statement
    // left behind by switching type would otherwise build an attestation the
    // user cannot see and cannot fix.
    this.attestationTargets.forEach((el) => {
      el.querySelectorAll("input, select, textarea").forEach((field) => {
        field.disabled = !isAttestation
      })
    })
  }
}
