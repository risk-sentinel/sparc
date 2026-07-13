import { Controller } from "@hotwired/stimulus"

// Auto-shows a Bootstrap 5 modal with import quality warnings.
// The "Acknowledge & Dismiss" button sends a PATCH to acknowledge
// the warnings so the modal doesn't re-appear on subsequent visits.
//
// Usage:
//   <div data-controller="import-warnings"
//        data-import-warnings-acknowledge-url-value="/control_catalogs/1/acknowledge_warnings">
//     <div data-import-warnings-target="modal" class="modal fade">...</div>
//   </div>
export default class ImportWarningsController extends Controller {
  static targets = ["modal"]
  static values = { acknowledgeUrl: String }

  connect() {
    if (typeof bootstrap === "undefined") return

    this.bsModal = new bootstrap.Modal(this.modalTarget, {
      backdrop: "static",
      keyboard: false
    })
    this.bsModal.show()
  }

  async acknowledge() {
    // Send PATCH to mark warnings as acknowledged
    if (this.acknowledgeUrlValue) {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      try {
        await fetch(this.acknowledgeUrlValue, {
          method: "PATCH",
          headers: {
            "X-CSRF-Token": csrfToken,
            "Accept": "application/json"
          }
        })
      } catch (e) {
        // Dismiss modal even if PATCH fails — non-critical
        console.warn("Failed to acknowledge warnings:", e)
      }
    }

    this.bsModal.hide()
  }

  disconnect() {
    if (this.bsModal) {
      this.bsModal.dispose()
      this.bsModal = null
    }
  }
}
