import { Controller } from "@hotwired/stimulus"

// 1.18.0-rf #1304 — a document page's section links stick just below the top
// bar, which is itself sticky (Bootstrap `sticky-top`) and changes height with
// the window (78px wide, 55px on a phone). This measures the bar and publishes
// its height as --sparc-topbar-h on <html>, which the section row's `top` and
// the sections' scroll-margin read. Set through the CSSOM, so it needs no
// inline style and is allowed under the strict CSP.
export default class StickyOffsetController extends Controller {
  connect() {
    this.bar = document.querySelector("nav.sticky-top")
    if (!this.bar) return

    this.publish = () => document.documentElement.style.setProperty("--sparc-topbar-h", `${this.bar.offsetHeight}px`)
    this.publish()
    this.observer = new ResizeObserver(this.publish)
    this.observer.observe(this.bar)
  }

  disconnect() {
    this.observer?.disconnect()
  }
}
