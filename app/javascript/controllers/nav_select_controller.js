import { Controller } from "@hotwired/stimulus"

// Navigates to the value of a <select> when it changes (#647, epic #650).
// Replaces the inline onchange="if(this.value) window.location=this.value;"
// handler, which strict CSP (script-src :self, no 'unsafe-inline') silently
// blocked, leaving the filter <select> inert.
export default class extends Controller {
  go(event) {
    if (event.target.value) window.location = event.target.value
  }
}
