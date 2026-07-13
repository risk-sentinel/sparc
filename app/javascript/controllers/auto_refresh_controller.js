import { Controller } from "@hotwired/stimulus"

// Auto-refresh for poll-until-done pages (document conversion / processing).
//
// Replaces <meta http-equiv="refresh"> which fails the axe `meta-refresh`
// rule (WCAG 2.2.1 Timing Adjustable) and hard-reloads the page, throwing
// away focus and scroll position. This refreshes via a Turbo visit with
// action: "replace" so navigation state is preserved and the reload is far
// less disruptive to keyboard / screen-reader users.
//
// Rendered conditionally (same as the old <meta>): the element only exists
// while something is still processing, so when the work completes the next
// render omits it and the polling stops.
//
//   <div data-controller="auto-refresh"
//        data-auto-refresh-interval-value="10000" hidden></div>
export default class AutoRefreshController extends Controller {
  static values = { interval: { type: Number, default: 10000 } }

  connect() {
    this.timer = setTimeout(() => {
      if (window.Turbo) {
        window.Turbo.visit(window.location.href, { action: "replace" })
      } else {
        window.location.reload()
      }
    }, this.intervalValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
