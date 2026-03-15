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

  // Fetch readiness and show the modal.
  // If controls are missing prioritization (Profile-specific), show a warning
  // banner instead of the modal — prioritization can't be fixed inline.
  async open() {
    try {
      const response = await fetch(this.checkUrlValue, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()

      // Block modal when prioritization is incomplete — this requires
      // the user to go back and assign P1/P2/P3 to every control first.
      const checks = data.checks || {}
      if (checks.controls_prioritized === false) {
        this.showPrioritizationWarning(data)
        return
      }

      this.renderModal(data)
      this.modalTarget.style.display = "block"
      this.backdropTarget.style.display = "block"
      document.body.style.overflow = "hidden"
    } catch (error) {
      console.error("Failed to check publication readiness:", error)
      alert("Failed to check publication readiness. Please try again.")
    }
  }

  // Show a dismissible warning banner when controls lack prioritization.
  showPrioritizationWarning(data) {
    // Remove any existing banner first
    const existing = document.getElementById("prioritization-warning-banner")
    if (existing) existing.remove()

    // Count unprioritized controls from the errors array
    const errorMsg = (data.errors || []).find(e => e.match(/missing prioritization/))
    const message = errorMsg
      ? `${errorMsg}. All controls must be prioritized before publishing.`
      : "Controls are missing prioritization (P1/P2/P3). All controls must be prioritized before publishing."

    const banner = document.createElement("div")
    banner.id = "prioritization-warning-banner"
    banner.className = "alert alert-warning alert-dismissible fade show d-flex align-items-center"
    banner.setAttribute("role", "alert")
    banner.style.cssText = "margin-bottom: 1rem; font-size: 0.95rem;"
    banner.innerHTML = `
      <svg class="bi flex-shrink-0 me-2" width="20" height="20" fill="currentColor" viewBox="0 0 16 16">
        <path d="M8.982 1.566a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>
      </svg>
      <div>${message}</div>
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `

    // Insert at the top of the main content area
    const main = document.querySelector("main") || document.querySelector(".container") || document.body.firstElementChild
    main.prepend(banner)

    // Scroll to the banner so the user sees it
    banner.scrollIntoView({ behavior: "smooth", block: "start" })
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
