import { Controller } from "@hotwired/stimulus"

// #1047 — a progress bar's width, set through the CSSOM.
//
// `style="width: <%= pct %>%"` cannot survive removing `style-src
// 'unsafe-inline'`: a style attribute is blocked whatever it contains, and a
// percentage is continuous so it cannot become a class the way the status
// colours can. Writing `element.style.width` is NOT what `style-src` governs —
// that covers style attributes in markup and <style> blocks — so this is the
// CSP-safe way to keep the exact value.
//
// Same approach #650 used on the ATO wizard when strict CSP silently killed its
// inline onclick handlers.
//
// Markup contract:
//   <div class="sparc-bar-fill" data-controller="bar" data-bar-pct-value="73.4">
//
// The class starts the bar at width 0, so with JS unavailable the bar renders
// empty rather than full — an under-report, which is the safe direction for a
// compliance figure.
export default class BarController extends Controller {
  static values = { pct: Number }

  connect() {
    this.render()
  }

  pctValueChanged() {
    this.render()
  }

  render() {
    const pct = Number.isFinite(this.pctValue) ? this.pctValue : 0
    this.element.style.width = `${Math.min(Math.max(pct, 0), 100)}%`
  }
}
