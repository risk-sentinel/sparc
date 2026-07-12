import { Controller } from "@hotwired/stimulus"

// Auto-dismiss flash notifications after a delay.
// Close button allows immediate dismissal.
export default class FlashController extends Controller {
  static targets = ["message"]

  connect() {
    this.messageTargets.forEach((el) => {
      const delay = el.classList.contains("alert-danger") ? 12000 : 8000
      setTimeout(() => this.autoDismiss(el), delay)
    })
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
