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
export default class ConsentBannerController extends Controller {
  static targets = ["modal", "loginCard", "errorArea"]

  // #824 — acceptance is remembered for the browser SESSION only.
  //
  // Session scope is the deliberate middle ground: AC-8 wants the notice shown
  // before access is granted, so a long-lived cookie that suppresses it for
  // weeks is not acceptable; but re-firing on every page load broke PIV login
  // outright, because the banner kept interposing between the card-bearing
  // request and /auth/piv. Once per browser session satisfies both.
  static STORAGE_KEY = "sparc.consent.accepted"

  connect() {
    if (typeof bootstrap === "undefined") return

    if (this.#alreadyAccepted()) {
      this.#revealLogin()
      return
    }

    this.bsModal = new bootstrap.Modal(this.modalTarget, {
      backdrop: "static",
      keyboard: false
    })
    this.bsModal.show()
  }

  proceed() {
    this.#remember()
    this.bsModal.hide()
    this.#revealLogin()
  }

  #revealLogin() {
    this.loginCardTarget.classList.remove("d-none")
  }

  // Storage can throw (Safari private mode, disabled cookies, sandboxed
  // iframes). Failing to READ must fall back to SHOWING the banner — the
  // compliance-safe direction — and failing to WRITE must not block login.
  #alreadyAccepted() {
    try {
      return window.sessionStorage.getItem(ConsentBannerController.STORAGE_KEY) === "1"
    } catch {
      return false
    }
  }

  #remember() {
    try {
      window.sessionStorage.setItem(ConsentBannerController.STORAGE_KEY, "1")
    } catch {
      /* nothing to do — the banner will simply re-fire next load */
    }
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
