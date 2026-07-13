import { Controller } from "@hotwired/stimulus"

// Drives the shared OSCAL metadata panel (#645, epic #650):
//   - collapse toggle on the card header
//   - structured roles / parties / revisions repeaters (add + remove rows)
//   - "pre-fill from my profile" convenience
//   - merge structured + advanced JSON into the hidden submit field on submit
//
// Replaces the inline on* attribute handlers and the nonce'd <script> of
// global functions that strict CSP (script-src :self, no 'unsafe-inline')
// silently blocked — and which built rows via innerHTML string concatenation
// that re-emitted onclick attributes (an injection-shaped pattern). New rows
// now come from inert <template> elements, so no markup is ever assembled
// from strings.
export default class OscalMetadataController extends Controller {
  static targets = [
    "body", "icon",
    "rolesEditor", "partiesEditor", "revisionsEditor",
    "roleTemplate", "partyTemplate", "revisionTemplate",
    "remarks", "advancedJson", "mergedJson", "editSection"
  ]

  toggle() {
    this.bodyTarget.classList.toggle("d-none")
    this.iconTarget.textContent =
      this.bodyTarget.classList.contains("d-none") ? "+" : "-"
  }

  addRole() { this.#append(this.rolesEditorTarget, this.roleTemplateTarget) }
  addParty() { this.#append(this.partiesEditorTarget, this.partyTemplateTarget) }
  addRevision() { this.#append(this.revisionsEditorTarget, this.revisionTemplateTarget) }

  removeRow(event) {
    const row = event.target.closest(".role-row, .party-row, .revision-row")
    if (row) row.remove()
  }

  prefill() {
    if (!this.hasEditSectionTarget) return
    const { userName = "", orgName = "" } = this.editSectionTarget.dataset

    if (this.rolesEditorTarget.querySelectorAll(".role-row").length === 0) {
      this.addRole()
      const row = this.rolesEditorTarget.querySelector(".role-row:last-child")
      this.#set(row, "id", "prepared-by")
      this.#set(row, "title", "Prepared By")
    }

    if (this.partiesEditorTarget.querySelectorAll(".party-row").length === 0) {
      this.addParty()
      const row = this.partiesEditorTarget.querySelector(".party-row:last-child")
      if (orgName) {
        this.#set(row, "name", orgName)
        this.#set(row, "type", "organization")
      } else if (userName) {
        this.#set(row, "name", userName)
        this.#set(row, "type", "person")
      }
    }
  }

  // Bound to the form's submit event. Builds the merged hidden JSON from the
  // structured editors + the advanced JSON textarea. Aborts the submit if the
  // advanced JSON is invalid.
  sync(event) {
    const roles = this.#collect(this.rolesEditorTarget, ["id", "title", "description"])
    const parties = this.#collect(this.partiesEditorTarget, ["name", "type", "uuid"])
    parties.forEach((p) => { if (!p.uuid) p.uuid = crypto.randomUUID() })
    const revisions = this.#collect(this.revisionsEditorTarget, ["version", "title", "published", "last-modified"])
    const remarks = this.hasRemarksTarget ? this.remarksTarget.value.trim() : ""

    let advanced = {}
    if (this.hasAdvancedJsonTarget && this.advancedJsonTarget.value.trim()) {
      try {
        advanced = JSON.parse(this.advancedJsonTarget.value)
        Object.keys(advanced).forEach((key) => {
          if (Array.isArray(advanced[key])) {
            advanced[key] = advanced[key].filter((item) =>
              Object.values(item).some((v) => v !== null && v !== ""))
            if (advanced[key].length === 0) delete advanced[key]
          }
        })
      } catch {
        if (event) event.preventDefault()
        alert("Invalid JSON in advanced metadata editor. Please fix the JSON syntax before saving.")
        return
      }
    }

    const merged = Object.assign({}, advanced)
    if (roles.length) merged.roles = roles
    if (parties.length) merged.parties = parties
    if (revisions.length) merged.revisions = revisions
    if (remarks) merged.remarks = remarks

    this.mergedJsonTarget.value = JSON.stringify(merged)
    // Clear the advanced textarea's name so only the merged hidden field submits.
    if (this.hasAdvancedJsonTarget) this.advancedJsonTarget.removeAttribute("name")
  }

  #append(container, template) {
    container.appendChild(template.content.cloneNode(true))
  }

  #set(row, field, value) {
    if (!row) return
    const el = row.querySelector(`[data-field="${field}"]`)
    if (el) el.value = value
  }

  #collect(container, fields) {
    const items = []
    container.querySelectorAll(":scope > div").forEach((row) => {
      const item = {}
      let hasValue = false
      fields.forEach((field) => {
        const el = row.querySelector(`[data-field="${field}"]`)
        if (el && el.value.trim() !== "") {
          item[field] = el.value.trim()
          hasValue = true
        }
      })
      if (hasValue) items.push(item)
    })
    return items
  }
}
