import { Controller } from "@hotwired/stimulus"

// Debounced auto-submit for the shared artifact-index search field (#672).
// Submits the GET form via Turbo Drive (requestSubmit) so the list updates
// without a full browser reload. Server-side filtering is done by the shared
// Model.search_text scope (the same scope the Api::V1 ?q endpoints use).
//
// CSP-safe: wired via a Stimulus data-action, never an inline on* handler.
export default class IndexSearchController extends Controller {
  static targets = ["form"]
  static values = { delay: { type: Number, default: 250 } }

  submit() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.formTarget.requestSubmit(), this.delayValue)
  }

  disconnect() {
    clearTimeout(this._timer)
  }
}
