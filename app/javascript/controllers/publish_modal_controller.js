import { Controller } from "@hotwired/stimulus"

// Stimulus controller for the smart publication modal.
//
// When the user clicks "Publish", this fetches metadata readiness from the
// server and displays a modal with a checklist and inline fix fields.
//
// Values:
//   check-url  — GET endpoint returning readiness JSON
//   publish-url — PATCH endpoint to publish the document
//   csrf-token  — Rails CSRF token for form submission
export default class extends Controller {
  static targets = [
    "modal", "backdrop", "checklist", "fixFields", "publishBtn",
    "creatorName", "contactName", "contactEmail", "contactType"
  ]

  static values = {
    checkUrl: String,
    publishUrl: String,
    csrfToken: String
  }

  // Fetch readiness and show the modal
  async open() {
    try {
      const response = await fetch(this.checkUrlValue, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()
      this.renderModal(data)
      this.modalTarget.style.display = "block"
      this.backdropTarget.style.display = "block"
      document.body.style.overflow = "hidden"
    } catch (error) {
      console.error("Failed to check publication readiness:", error)
      alert("Failed to check publication readiness. Please try again.")
    }
  }

  close() {
    this.modalTarget.style.display = "none"
    this.backdropTarget.style.display = "none"
    document.body.style.overflow = ""
  }

  renderModal(data) {
    // Render checklist
    const checks = data.checks || {}
    let checklistHtml = ""

    checklistHtml += this.checkItem("Creator/Prepared-by role", checks.creator_role)
    checklistHtml += this.checkItem("Contact party", checks.contact_party)
    checklistHtml += this.checkItem("Responsible parties linked", checks.responsible_parties)
    if (checks.controls_prioritized !== undefined) {
      checklistHtml += this.checkItem("All controls prioritized (P1/P2/P3)", checks.controls_prioritized)
    }
    checklistHtml += this.infoItem("Title", checks.title)
    checklistHtml += this.infoItem("OSCAL version", checks.oscal_version)

    this.checklistTarget.innerHTML = checklistHtml

    // Show/hide inline fix fields
    const defaults = data.defaults || {}
    const needsFixes = !data.ready

    if (needsFixes) {
      this.fixFieldsTarget.style.display = "block"
      // Pre-fill from user profile defaults
      if (this.hasCreatorNameTarget)
        this.creatorNameTarget.value = defaults.creator_name || ""
      if (this.hasContactNameTarget)
        this.contactNameTarget.value = defaults.org_name || defaults.creator_name || ""
      if (this.hasContactEmailTarget)
        this.contactEmailTarget.value = defaults.org_email || defaults.creator_email || ""
      if (this.hasContactTypeTarget)
        this.contactTypeTarget.value = defaults.party_type || "organization"
    } else {
      this.fixFieldsTarget.style.display = "none"
    }

    // Update publish button state
    this.publishBtnTarget.textContent = data.ready ? "Confirm & Publish" : "Fix & Publish"
  }

  checkItem(label, ok) {
    const icon = ok ? "✅" : "❌"
    const cls = ok ? "text-success" : "text-danger fw-semibold"
    return `<div class="${cls}" style="margin-bottom: 0.35rem;">${icon} ${label}</div>`
  }

  infoItem(label, ok) {
    const icon = ok ? "ℹ️" : "⚠️"
    return `<div class="text-body-secondary" style="margin-bottom: 0.35rem;">${icon} ${label} ${ok ? "(set)" : "(will be auto-generated)"}</div>`
  }

  async confirmPublish() {
    this.publishBtnTarget.disabled = true
    this.publishBtnTarget.textContent = "Publishing..."

    try {
      const formData = new FormData()
      formData.append("_method", "PATCH")
      formData.append("authenticity_token", this.csrfTokenValue)

      // Gather inline fixes if the fix fields are visible
      if (this.fixFieldsTarget.style.display !== "none") {
        const creatorName = this.hasCreatorNameTarget ? this.creatorNameTarget.value.trim() : ""
        const contactName = this.hasContactNameTarget ? this.contactNameTarget.value.trim() : ""
        const contactEmail = this.hasContactEmailTarget ? this.contactEmailTarget.value.trim() : ""
        const contactType = this.hasContactTypeTarget ? this.contactTypeTarget.value : "organization"

        if (creatorName) {
          formData.append("metadata_fixes[roles]", JSON.stringify([
            { "id": "prepared-by", "title": creatorName }
          ]))
        }

        if (contactName) {
          const partyUuid = crypto.randomUUID()
          const party = {
            "uuid": partyUuid,
            "type": contactType,
            "name": contactName
          }
          if (contactEmail) party["email-addresses"] = [contactEmail]

          formData.append("metadata_fixes[parties]", JSON.stringify([party]))
          formData.append("metadata_fixes[responsible_parties]", JSON.stringify([
            { "role-id": "prepared-by", "party-uuids": [partyUuid] }
          ]))
        }
      }

      const response = await fetch(this.publishUrlValue, {
        method: "POST",
        body: formData
      })

      // Follow redirect (Turbo will handle this, but fallback for non-Turbo)
      if (response.redirected) {
        window.location.href = response.url
      } else {
        window.location.reload()
      }
    } catch (error) {
      console.error("Publication failed:", error)
      this.publishBtnTarget.disabled = false
      this.publishBtnTarget.textContent = "Retry Publish"
      alert("Publication failed. Please try again.")
    }
  }

  scrollToMetadata() {
    this.close()
    const metadataSection = document.querySelector("[data-oscal-metadata-section]")
    if (metadataSection) {
      metadataSection.scrollIntoView({ behavior: "smooth", block: "start" })
      // Open the details element if collapsed
      const details = metadataSection.closest("details")
      if (details) details.open = true
    }
  }
}
