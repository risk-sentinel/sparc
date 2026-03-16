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

  // Show a blocking modal when controls lack prioritization.
  // The user must acknowledge and return to the baseline to fix it.
  showPrioritizationWarning(data) {
    // Remove any existing warning modal first
    const existing = document.getElementById("prioritization-warning-modal")
    if (existing) existing.remove()
    const existingBackdrop = document.getElementById("prioritization-warning-backdrop")
    if (existingBackdrop) existingBackdrop.remove()

    // Extract the count from the errors array
    const errorMsg = (data.errors || []).find(e => e.match(/missing prioritization/))
    const message = errorMsg
      ? `${errorMsg}.`
      : "Controls are missing prioritization (P1/P2/P3)."

    // Create backdrop
    const backdrop = document.createElement("div")
    backdrop.id = "prioritization-warning-backdrop"
    backdrop.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1050;"

    // Create modal
    const modal = document.createElement("div")
    modal.id = "prioritization-warning-modal"
    modal.setAttribute("role", "dialog")
    modal.setAttribute("aria-modal", "true")
    modal.style.cssText = "position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:1055;background:#fff;border-radius:0.75rem;padding:2rem;max-width:480px;width:90%;box-shadow:0 10px 40px rgba(0,0,0,0.3);"

    modal.innerHTML = `
      <div style="text-align:center;margin-bottom:1.25rem;">
        <svg width="48" height="48" fill="#e8a317" viewBox="0 0 16 16" style="margin-bottom:0.75rem;">
          <path d="M8.982 1.566a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>
        </svg>
        <h5 style="margin:0 0 0.5rem;font-weight:600;color:#333;">Prioritization Required</h5>
      </div>
      <p style="margin:0 0 1rem;color:#555;font-size:0.95rem;line-height:1.5;">
        ${message}
      </p>
      <p style="margin:0 0 1.5rem;color:#555;font-size:0.95rem;line-height:1.5;">
        All controls must have a priority level (P1, P2, or P3) assigned before this baseline can be published.
      </p>
      <div style="text-align:center;">
        <button id="prioritization-warning-ok-btn" type="button"
                class="btn btn-warning"
                style="min-width:180px;font-weight:500;">
          Return to Baseline
        </button>
      </div>
    `

    document.body.appendChild(backdrop)
    document.body.appendChild(modal)
    document.body.style.overflow = "hidden"

    // Close on button click
    const closeWarning = () => {
      modal.remove()
      backdrop.remove()
      document.body.style.overflow = ""
    }

    modal.querySelector("#prioritization-warning-ok-btn").addEventListener("click", closeWarning)
    backdrop.addEventListener("click", closeWarning)
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
