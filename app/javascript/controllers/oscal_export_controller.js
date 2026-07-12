import { Controller } from "@hotwired/stimulus"

// Stimulus controller for OSCAL export with validation.
//
// When a user clicks an export link (JSON/YAML/XML), this controller:
//   1. Fetches a validation endpoint to check OSCAL compliance
//   2. If valid  → triggers the download immediately
//   3. If invalid → shows a confirmation modal with errors and a "Continue" option
//
// Usage (on each export link):
//   data-action="click->oscal-export#download"
//   data-oscal-export-validate-url-param="/ssp_documents/1/validate_oscal_export"
//   data-oscal-export-download-url-param="/ssp_documents/1/download_oscal_validated"
//   data-oscal-export-fallback-url-param="/ssp_documents/1/download_oscal_unvalidated"
//   data-oscal-export-format-param="JSON"
//   data-oscal-export-doc-type-param="SSP"
export default class OscalExportController extends Controller {

  // #451 A2: when a controller redirects from a failed validated download
  // (?oscal_validation_failed=1&oscal_format=json|yaml|xml) the show page
  // lands without any user click. Auto-trigger the same modal flow as a
  // dropdown click so the user sees the specific validation errors.
  connect() {
    const url = new URL(window.location)
    if (url.searchParams.get("oscal_validation_failed") !== "1") return

    const format = (url.searchParams.get("oscal_format") || "json").toUpperCase()
    const link = this.element.querySelector(`[data-oscal-export-format-param="${format}"]`)
    if (!link) return

    // Strip the params so refresh doesn't re-open the modal.
    url.searchParams.delete("oscal_validation_failed")
    url.searchParams.delete("oscal_format")
    window.history.replaceState({}, "", url.toString())

    // Defer to next tick so all controllers in the dropdown have connected.
    requestAnimationFrame(() => {
      this.download({ preventDefault: () => {}, currentTarget: link })
    })
  }

  async download(event) {
    event.preventDefault()

    const link = event.currentTarget
    const validateUrl = link.dataset.oscalExportValidateUrlParam
    const downloadUrl = link.dataset.oscalExportDownloadUrlParam
    const fallbackUrl = link.dataset.oscalExportFallbackUrlParam
    const format      = link.dataset.oscalExportFormatParam || "JSON"
    const docType     = link.dataset.oscalExportDocTypeParam || "Document"

    // Show loading state
    const originalText = link.textContent
    link.textContent = `Validating...`
    link.style.pointerEvents = "none"

    try {
      const response = await fetch(validateUrl, {
        headers: { "Accept": "application/json" }
      })
      const data = await response.json()

      // Restore link state
      link.textContent = originalText
      link.style.pointerEvents = ""

      if (data.valid) {
        window.location.href = downloadUrl
      } else {
        this.showConfirmModal(data, format, docType, fallbackUrl)
      }
    } catch (error) {
      console.error("OSCAL export validation failed:", error)
      link.textContent = originalText
      link.style.pointerEvents = ""
      // Fall back to direct download on network error
      window.location.href = downloadUrl
    }
  }

  showConfirmModal(data, format, docType, fallbackUrl) {
    // Remove any existing modal
    this.removeModal()

    // Create backdrop
    const backdrop = document.createElement("div")
    backdrop.id = "oscal-export-backdrop"
    backdrop.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.5);z-index:1050;"

    // Create modal
    const modal = document.createElement("div")
    modal.id = "oscal-export-modal"
    modal.setAttribute("role", "dialog")
    modal.setAttribute("aria-modal", "true")
    modal.style.cssText = "position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);z-index:1055;background:var(--bs-body-bg, #fff);color:var(--bs-body-color, #333);border-radius:0.75rem;padding:2rem;max-width:520px;width:90%;box-shadow:0 10px 40px rgba(0,0,0,0.3);"

    // Build error list
    const errors = data.errors || []
    let errorHtml = ""
    if (errors.length > 0) {
      const errorItems = errors.map(e => {
        const escaped = e.replaceAll(/</g, "&lt;").replaceAll(/>/g, "&gt;")
        return `<li style="margin-bottom:0.3rem;">${escaped}</li>`
      }).join("")
      errorHtml = `
        <details style="margin:0.75rem 0 1rem;background:rgba(231,76,60,0.06);border:1px solid rgba(231,76,60,0.15);border-radius:6px;padding:0.6rem 0.8rem;">
          <summary style="cursor:pointer;font-size:0.82rem;font-weight:500;color:var(--bs-body-color, #555);">
            ${errors.length} validation error${errors.length === 1 ? '' : 's'}
          </summary>
          <ul style="margin:0.5rem 0 0;padding-left:1.2rem;font-size:0.78rem;color:var(--bs-body-color, #666);line-height:1.5;">
            ${errorItems}
          </ul>
        </details>
      `
    }

    modal.innerHTML = `
      <div style="text-align:center;margin-bottom:1rem;">
        <svg width="48" height="48" fill="#e8a317" viewBox="0 0 16 16" style="margin-bottom:0.75rem;">
          <path d="M8.982 1.566a1.13 1.13 0 0 0-1.96 0L.165 13.233c-.457.778.091 1.767.98 1.767h13.713c.889 0 1.438-.99.98-1.767L8.982 1.566zM8 5c.535 0 .954.462.9.995l-.35 3.507a.552.552 0 0 1-1.1 0L7.1 5.995A.905.905 0 0 1 8 5zm.002 6a1 1 0 1 1 0 2 1 1 0 0 1 0-2z"/>
        </svg>
        <h5 style="margin:0 0 0.5rem;font-weight:600;">${docType} is not valid OSCAL</h5>
      </div>
      <p style="margin:0 0 0.25rem;font-size:0.92rem;line-height:1.5;text-align:center;">
        Proceed with exporting non-OSCAL compliant in ${format} format?
      </p>
      ${errorHtml}
      <div class="d-flex justify-content-center gap-2" style="margin-top:1.25rem;">
        <button id="oscal-export-cancel-btn" type="button"
                class="btn btn-outline-secondary"
                style="min-width:100px;font-weight:500;">
          Cancel
        </button>
        <button id="oscal-export-continue-btn" type="button"
                class="btn btn-warning"
                style="min-width:100px;font-weight:500;">
          Continue
        </button>
      </div>
    `

    document.body.appendChild(backdrop)
    document.body.appendChild(modal)
    document.body.style.overflow = "hidden"

    // Event handlers
    const close = () => this.removeModal()

    modal.querySelector("#oscal-export-cancel-btn").addEventListener("click", close)
    backdrop.addEventListener("click", close)

    modal.querySelector("#oscal-export-continue-btn").addEventListener("click", () => {
      close()
      window.location.href = fallbackUrl
    })

    // Escape key
    this._escHandler = (e) => { if (e.key === "Escape") close() }
    document.addEventListener("keydown", this._escHandler)
  }

  removeModal() {
    const modal = document.getElementById("oscal-export-modal")
    const backdrop = document.getElementById("oscal-export-backdrop")
    if (modal) modal.remove()
    if (backdrop) backdrop.remove()
    document.body.style.overflow = ""
    if (this._escHandler) {
      document.removeEventListener("keydown", this._escHandler)
      this._escHandler = null
    }
  }
}
