import { Controller } from "@hotwired/stimulus"

// On SSP selection, auto-fill the Baseline Profile select from the ssp->profile
// map carried on the SSP <select>'s data-ssp-profile-map. Replaces the former
// inline <script> in sap_documents/new — CSP / Turbo-nonce safe (#528).
export default class SspProfileSyncController extends Controller {
  static targets = ["profile"]

  populate(event) {
    const map = JSON.parse(event.target.dataset.sspProfileMap || "{}")
    const profileId = map[event.target.value]
    if (profileId && this.hasProfileTarget) {
      this.profileTarget.value = profileId
    }
  }
}
