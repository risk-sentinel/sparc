import { Controller } from "@hotwired/stimulus"

// Swaps disclosure arrows (▶ closed / ▼ open) for every <details> inside the
// element, syncing on toggle. Attached globally on <body> in the layout so it
// covers all pages and survives Turbo navigation WITHOUT a per-page inline
// <script>. Turbo Drive re-executes a page's inline scripts on navigation by
// cloning them, and cloned scripts lose their per-request CSP nonce, tripping a
// script-src-elem violation under the enforced CSP (#712 / #528).
//
// Known arrow classes across the show pages + the data-quality card + the SAR
// heatmap. Explicit list (not a wildcard) so unrelated classes like "narrow"
// never match.
const ARROWS = [
  ".card-arrow",
  ".ctx-arrow",
  ".catalog-arrow",
  ".inherited-arrow",
  ".data-quality-arrow",
  ".sparc-section-arrow",
].join(", ")

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("details").forEach((details) => {
      const sync = () => {
        const summary = details.querySelector(":scope > summary")
        if (!summary) return
        summary.querySelectorAll(ARROWS).forEach((arrow) => {
          arrow.innerHTML = details.open ? "&#9660;" : "&#9658;"
        })
      }
      details.addEventListener("toggle", sync)
      sync()
    })
  }
}
