import { Controller } from "@hotwired/stimulus"

// Drives the SSP "Enrich" form repeaters (epic #650):
//   - add Information Type / Component / User rows
//
// Replaces the inline on* attribute handlers and the nonce'd <script> of
// global addX() functions that strict CSP (script-src :self, no
// 'unsafe-inline') silently blocked — and which built rows via
// insertAdjacentHTML string concatenation (an injection-shaped pattern).
// New rows now clone inert <template> elements, so no markup is ever
// assembled from strings.
export default class extends Controller {
  static targets = [
    "infoTypesContainer", "componentsContainer", "usersContainer",
    "infoTypeTemplate", "componentTemplate", "userTemplate"
  ]

  addInfoType() { this.#append(this.infoTypesContainerTarget, this.infoTypeTemplateTarget) }
  addComponent() { this.#append(this.componentsContainerTarget, this.componentTemplateTarget) }
  addUser() { this.#append(this.usersContainerTarget, this.userTemplateTarget) }

  #append(container, template) {
    container.appendChild(template.content.cloneNode(true))
  }
}
