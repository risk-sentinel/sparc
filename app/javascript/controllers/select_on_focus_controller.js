import { Controller } from "@hotwired/stimulus"

// Selects the whole value when the field is focused or clicked, so a one-time
// secret can be copied in a single gesture (#841).
//
// A Stimulus controller rather than an inline `onfocus=`: the page-level CSP
// has no 'unsafe-inline' in script-src, so an inline handler is silently
// blocked by the browser and the convenience just never happens.
export default class SelectOnFocusController extends Controller {
  selectAll() {
    this.element.select()
  }
}
