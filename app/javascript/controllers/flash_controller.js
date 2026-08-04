import { Controller } from "@hotwired/stimulus"

// Flash notification lifecycle.
//
// Success and warning messages fade on their own — they confirm something the
// user already believes happened, so a transient toast is enough.
//
// Errors do NOT. An error that fades is a failure the user can miss entirely,
// which is the whole complaint in #902: a rejected evidence upload read as
// "nothing happened". Errors stay on screen until the user dismisses them, so
// a failure always requires acknowledgement rather than attention within a
// 12-second window. (Errors auto-dismissed at 12s between 2026-03-06 and this
// change — an unintended side effect of restyling flash as a toast overlay.)
export default class FlashController extends Controller {
  static targets = ["message"]

  static AUTO_DISMISS_MS = 8000

  connect() {
    this.timers = []

    this.messageTargets.forEach((el) => {
      if (this.constructor.persistent(el)) return

      this.timers.push(
        setTimeout(() => this.autoDismiss(el), this.constructor.AUTO_DISMISS_MS)
      )
    })
  }

  disconnect() {
    // Turbo caches and restores pages; a timer left running from a previous
    // visit would dismiss a message belonging to the current one.
    this.timers.forEach(clearTimeout)
    this.timers = []
  }

  // Errors require an explicit dismissal.
  static persistent(el) {
    return el.classList.contains("alert-danger")
  }

  dismiss(event) {
    const el = event.currentTarget.closest(".alert")
    if (el) this.fadeOut(el)
  }

  autoDismiss(el) {
    if (el.isConnected && !el.classList.contains("dismissing")) {
      this.fadeOut(el)
    }
  }

  fadeOut(el) {
    el.classList.add("dismissing")
    el.addEventListener("animationend", () => el.remove(), { once: true })
  }
}
