import { Controller } from "@hotwired/stimulus"

// Enables/disables the boundary picker when the CDEF scope radio switches
// between boundary-specific and global (#395). Replaces the former inline
// <script> in _scope_picker — CSP / Turbo-nonce safe (#528). The markup already
// declared the action + radio targets; this supplies the missing controller.
export default class CdefScopeController extends Controller {
  static targets = ["boundaryRadio", "globalRadio", "wrapper"]

  connect() {
    this.toggle()
  }

  // The `disabled` attribute carries the inert state on its own: browsers grey
  // the control natively and assistive tech reads it, so nothing here needs to
  // restate it visually.
  //
  // #929 — this used to also set `opacity: 0.5` on the WRAPPER, which dimmed the
  // label and helper text along with the select. A disabled form control is
  // exempt from contrast rules; the surrounding text is not. Measured on the
  // CDEF show page, where a globally-available component definition renders with
  // the global radio already checked: #666 at half opacity resolves to #b3b3b3
  // on white — 2.09:1 against a required 4.5:1, the first WCAG A/AA violation on
  // that page. Fading text to convey state fails the same way wherever it is
  // done, so the fade is gone rather than tuned.
  toggle() {
    if (!this.hasWrapperTarget) return
    const disabled = this.hasGlobalRadioTarget && this.globalRadioTarget.checked
    const picker = this.wrapperTarget.querySelector("select")
    if (picker) picker.disabled = disabled
  }
}
