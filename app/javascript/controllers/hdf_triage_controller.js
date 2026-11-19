import { Controller } from "@hotwired/stimulus"

// #447 — HDF triage disposition form helper. When the override kind changes,
// update the hint that tells the user which record type the disposition must
// link. CSP-safe: driven by a Stimulus data-action, no inline handlers.
//
// The linkage map mirrors FindingDispositionService::LINKAGE (kept in sync by
// the request/service specs, which assert the same pairings).
const LINKAGE = {
  falsePositive: "Evidence",
  waiver: "Attestation (role: authorizing_official) + expiration",
  poam: "PoamFinding",
  vendorDependency: "PoamFinding",
  inherited: "AuthorizationBoundary (upstream)",
  riskAdjustment: "RiskAssessment",
  operationalRequirement: "Attestation (role: authorizing_official) + expiration",
  attestation: "Attestation"
}

export default class HdfTriageController extends Controller {
  static targets = ["kind", "hint", "impact", "impactInput"]

  showLinkage() {
    if (!this.hasKindTarget || !this.hasHintTarget) return
    const kind = this.kindTarget.value
    this.hintTarget.textContent = `Links a: ${LINKAGE[kind] || "—"}`
    this.toggleImpact(kind)
  }

  // #1368 — only a riskAdjustment carries an adjusted impact. A hidden field is
  // also disabled, so it is not submitted for any other kind.
  toggleImpact(kind) {
    if (!this.hasImpactTarget || !this.hasImpactInputTarget) return
    const adjusting = kind === "riskAdjustment"
    this.impactTarget.hidden = !adjusting
    this.impactInputTarget.disabled = !adjusting
    this.impactInputTarget.required = adjusting
  }
}
