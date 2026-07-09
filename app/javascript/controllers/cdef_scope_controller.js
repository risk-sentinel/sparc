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

  toggle() {
    if (!this.hasWrapperTarget) return
    const disabled = this.hasGlobalRadioTarget && this.globalRadioTarget.checked
    const picker = this.wrapperTarget.querySelector("select")
    if (picker) picker.disabled = disabled
    this.wrapperTarget.style.opacity = disabled ? "0.5" : "1"
  }
}
