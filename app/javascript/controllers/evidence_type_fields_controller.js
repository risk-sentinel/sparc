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

    // The dropzone enforces "a file is required" with its OWN capture-phase
    // submit guard (#902), because its real <input type="file"> is `d-none` and
    // a browser cannot report on a hidden required control. That guard reads
    // this value, so it has to move with the type — otherwise choosing
    // Attestation leaves it armed and the submit is cancelled before any
    // request is made, with the page looking like it simply ignored the click.
    // That is the exact defect #947 exists to remove, and it would have come
    // straight back in JavaScript.
    // Found by its own controller attribute rather than a target, so the shared
    // dropzone partial does not need to know this screen exists.
    this.element.querySelectorAll('[data-controller~="dropzone"]').forEach((el) => {
      el.setAttribute("data-dropzone-required-value", String(!isAttestation))
    })
  }
}
