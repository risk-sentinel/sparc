import { Controller } from "@hotwired/stimulus"

// Drives the SAR "Enrich" form repeaters (epic #650):
//   - add Result / Observation / Finding / Risk rows
//
// Replaces the inline on* attribute handlers and the nonce'd <script> of
// global addX() functions that strict CSP (script-src :self, no
// 'unsafe-inline') silently blocked — and which built rows via
// insertAdjacentHTML string concatenation (an injection-shaped pattern).
// New rows now clone inert <template> elements, so no markup is ever
// assembled from strings.
export default class extends Controller {
  static targets = [
    "resultsContainer", "observationsContainer", "findingsContainer", "risksContainer",
    "resultTemplate", "observationTemplate", "findingTemplate", "riskTemplate"
  ]

  addResult() { this.#append(this.resultsContainerTarget, this.resultTemplateTarget) }
  addObservation() { this.#append(this.observationsContainerTarget, this.observationTemplateTarget) }
  addFinding() { this.#append(this.findingsContainerTarget, this.findingTemplateTarget) }
  addRisk() { this.#append(this.risksContainerTarget, this.riskTemplateTarget) }

  #append(container, template) {
    container.appendChild(template.content.cloneNode(true))
  }
}
