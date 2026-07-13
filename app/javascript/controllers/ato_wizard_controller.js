import { Controller } from "@hotwired/stimulus"

// Drives the ATO Package Wizard step panels (#650 CSP epic):
//   - each step (profile, cdef, ssp, sap, sar, poam) has a group of radios
//     selecting a mode (create_new / select_existing / select / skip)
//   - selecting a radio updates the step's hidden _mode field and shows the
//     matching panel (create_new / select_existing / select) while hiding the
//     others
//
// Replaces the inline onclick="toggleMode('...')" attribute handlers and the
// nonce'd <script> defining toggleMode, which strict CSP (script-src :self,
// no 'unsafe-inline') silently blocked. Behavior is preserved exactly: same
// DOM ids, same show/hide logic. The dynamic step name is passed via a
// Stimulus action param (data-ato-wizard-mode-param) rather than interpolated
// into executable JS.
export default class AtoWizardController extends Controller {
  // Mirrors the original toggleMode(stepName): read the checked radio in the
  // step's group, write the hidden _mode field, then show only the relevant
  // panel for the selected mode.
  setMode(event) {
    const stepName = event.params.mode
    const radio = this.element.querySelector(`input[name="${stepName}_radio"]:checked`)
    if (!radio) return

    const mode = radio.value
    const hiddenField = document.getElementById(`${stepName}_mode`)
    if (hiddenField) hiddenField.value = mode

    // Hide all panels for this step
    const createPanel = document.getElementById(`${stepName}_create_new_panel`)
    const selectPanel = document.getElementById(`${stepName}_select_existing_panel`)
    const genericSelectPanel = document.getElementById(`${stepName}_select_panel`)

    if (createPanel) createPanel.style.display = "none"
    if (selectPanel) selectPanel.style.display = "none"
    if (genericSelectPanel) genericSelectPanel.style.display = "none"

    // Show the relevant panel
    if (mode === "create_new" && createPanel) {
      createPanel.style.display = "block"
    } else if (mode === "select_existing" && selectPanel) {
      selectPanel.style.display = "block"
    } else if (mode === "select" && genericSelectPanel) {
      genericSelectPanel.style.display = "block"
    }
  }
}
