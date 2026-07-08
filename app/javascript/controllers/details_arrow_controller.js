import { Controller } from "@hotwired/stimulus"

// Rotates a disclosure arrow (▶ closed / ▼ open) for any <details> inside the
// element, syncing on toggle. Replaces a former inline <script> in
// _data_quality_card: inline scripts are re-executed by Turbo on navigation and
// lose their per-request CSP nonce, tripping a script-src-elem violation
// (#712, part of the CSP inline-script refactor #528).
export default class extends Controller {
  connect() {
    this.element.querySelectorAll("details").forEach((details) => {
      const arrow = details.querySelector(".data-quality-arrow")
      if (!arrow) return
      const sync = () => { arrow.innerHTML = details.open ? "&#9660;" : "&#9658;" }
      details.addEventListener("toggle", sync)
      sync()
    })
  }
}
