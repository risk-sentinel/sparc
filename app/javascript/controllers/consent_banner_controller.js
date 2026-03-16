import { Controller } from "@hotwired/stimulus"

// Displays a Bootstrap 5 modal with consent/warning text on page load.
// The user must click "Proceed" to reveal the login card, or "Cancel"
// to see an error message and remain blocked from logging in.
//
// Usage (in login layout):
//   <div data-controller="consent-banner">
//     <div data-consent-banner-target="errorArea"></div>
//     <div data-consent-banner-target="loginCard" class="d-none">...</div>
//     <div data-consent-banner-target="modal" class="modal fade">...</div>
//   </div>
export default class extends Controller {
  static targets = ["modal", "loginCard", "errorArea"]

  connect() {
    if (typeof bootstrap === "undefined") return

    this.bsModal = new bootstrap.Modal(this.modalTarget, {
      backdrop: "static",
      keyboard: false
    })
    this.bsModal.show()
  }

  proceed() {
    this.bsModal.hide()
    this.loginCardTarget.classList.remove("d-none")
  }

  cancel() {
    this.bsModal.hide()
    this.errorAreaTarget.innerHTML = `
      <div class="alert alert-danger alert-dismissible fade show small" role="alert">
        Cannot login without consent
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
      </div>
    `
  }

  disconnect() {
    if (this.bsModal) {
      this.bsModal.dispose()
      this.bsModal = null
    }
  }
}
