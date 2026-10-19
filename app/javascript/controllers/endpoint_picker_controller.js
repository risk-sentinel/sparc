import { Controller } from "@hotwired/stimulus"

// #1176 — the API token endpoint picker. "All endpoints" and the per-resource
// Read/Write boxes are alternatives: ticking All clears and disables the rest
// (a disabled box is not submitted), unticking it hands the choice back.
//
// The server does not depend on this. "*" in the submitted list means every
// endpoint whatever else is ticked, and a submission with nothing ticked is
// refused, so the form means the same with JavaScript off.
//
// Usage: app/views/admin/api_tokens/_endpoint_picker.html.erb
export default class EndpointPickerController extends Controller {
  static targets = ["all", "entry"]

  connect() {
    this.sync()
  }

  sync() {
    const all = this.allTarget.checked
    this.entryTargets.forEach((box) => {
      if (all) box.checked = false
      box.disabled = all
    })
  }
}
