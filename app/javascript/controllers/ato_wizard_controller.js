import { Controller } from "@hotwired/stimulus"
import { setVisible } from "controllers/visibility"

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

    // #1047 — through `controllers/visibility`, never `style.display`.
    //
    // These panels carry `.sparc-wizard-step-panel .sparc-d-none`, and
    // `.sparc-d-none` is `display: none !important`. An inline
    // `style.display = "block"` CANNOT outrank `!important`, so once the sweep
    // moved the panels off `style="display:none"` this controller stopped being
    // able to open any of them — ten panels across the wizard, every step of it,
    // silently inert.
    //
    // The header below says "Behavior is preserved exactly: same DOM ids, same
    // show/hide logic." That stayed true of the LOGIC and stopped being true of
    // the RESULT, which is exactly the kind of break a comment cannot catch and
    // an interaction test can.
    setVisible(createPanel, false)
    setVisible(selectPanel, false)
    setVisible(genericSelectPanel, false)

    // Show the relevant panel
    if (mode === "create_new") {
      setVisible(createPanel, true)
    } else if (mode === "select_existing") {
      setVisible(selectPanel, true)
    } else if (mode === "select") {
      setVisible(genericSelectPanel, true)
    }
  }
}
