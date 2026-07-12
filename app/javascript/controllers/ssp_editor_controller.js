import { Controller } from "@hotwired/stimulus"

// Drives the stateful System Security Plan editor (editor.html.erb).
//   - load an existing SSP document (fetch its exported JSON)
//   - navigate / select records, display each control's fields
//   - edit editable fields and save current / all via the v1 API
//   - export the document JSON via the download route
//
// Replaces the inline on* attribute handlers and the nonce'd <script> of
// global functions that strict CSP (script-src :self, no 'unsafe-inline')
// silently blocked. Server-injected URLs arrive via static values
// (data-ssp-editor-*-value) rather than interpolated into executable JS, and
// table rows are built with createElement/textContent — never innerHTML that
// re-emits markup.
export default class SspEditorController extends Controller {
  static targets = [
    "documentSelector", "recordSelector",
    "notification", "navigationContainer", "legend",
    "headerInfo", "controlId", "controlTitle", "recordCounter",
    "dataTable", "tableBody", "actionButtons",
    "prevBtn", "nextBtn"
  ]

  static values = {
    apiBaseUrl: { type: String, default: "/api/v1" },
    downloadPath: { type: String, default: "/ssp_documents/__ID__/download_json" }
  }

  connect() {
    this.currentDocumentId = null
    this.currentData = null
    this.currentIndex = 0
  }

  get #csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // --- Load existing document -------------------------------------------

  async loadExistingDocument(event) {
    const documentId = event.target.value
    if (!documentId) return

    try {
      this.#showNotification("Loading document...", "info")

      const response = await fetch(
        `${this.apiBaseUrlValue}/ssp_documents/${documentId}/export`,
        { headers: { "X-CSRF-Token": this.#csrfToken } }
      )

      if (!response.ok) {
        throw new Error("Failed to load document")
      }

      const data = await response.json()
      this.currentDocumentId = documentId
      this.#loadConvertedJSON(data)
      this.#showNotification("Document loaded successfully!", "success")
    } catch (error) {
      console.error("Load error:", error)
      this.#showNotification(`Failed to load document: ${error.message}`, "error")
    }
  }

  #loadConvertedJSON(jsonData) {
    this.currentData = jsonData.controls || []
    this.currentIndex = 0

    if (this.currentData.length > 0) {
      this.#displayRecord(this.currentIndex)
      this.#populateRecordSelector()
      this.#showEditorUI()
    } else {
      this.#showNotification("No controls found in the document", "error")
    }
  }

  // --- Display ----------------------------------------------------------

  #displayRecord(index) {
    if (!this.currentData || this.currentData.length === 0) return

    const record = this.currentData[index]

    // Update header
    this.controlIdTarget.textContent = record.control_id
    this.controlTitleTarget.textContent = record.title

    // Update counter
    this.recordCounterTarget.textContent =
      `Record ${index + 1} of ${this.currentData.length}`

    // Update table
    const tableBody = this.tableBodyTarget
    tableBody.replaceChildren()

    record.fields.forEach((field) => {
      const row = tableBody.insertRow()
      const cellName = row.insertCell(0)
      const cellValue = row.insertCell(1)

      const label = field.field_name
        .replaceAll(/_/g, " ")
        .replace(/\b\w/g, (l) => l.toUpperCase())
      cellName.append(`${label} `)
      const icon = document.createElement("span")
      if (field.editable) {
        icon.style.color = "#27ae60"
        icon.textContent = "✏️"
      } else {
        icon.style.color = "#95a5a6"
        icon.textContent = "🔒"
      }
      cellName.append(icon)

      if (field.editable) {
        const textarea = document.createElement("textarea")
        textarea.rows = 3
        textarea.style.width = "100%"
        textarea.style.padding = "0.5rem"
        textarea.style.border = "1px solid #ddd"
        textarea.style.borderRadius = "4px"
        textarea.dataset.field = field.field_name
        textarea.value = field.field_value || ""
        cellValue.append(textarea)
      } else {
        cellValue.textContent = field.field_value || ""
      }
    })

    // Update navigation buttons
    this.prevBtnTarget.disabled = (index === 0)
    this.nextBtnTarget.disabled = (index === this.currentData.length - 1)
  }

  #populateRecordSelector() {
    const selector = this.recordSelectorTarget
    selector.replaceChildren()

    this.currentData.forEach((record, index) => {
      const option = document.createElement("option")
      option.value = index
      option.textContent = `${record.control_id} - ${record.title}`
      selector.appendChild(option)
    })

    selector.value = this.currentIndex
  }

  // --- Navigation -------------------------------------------------------

  navigatePrev() { this.#navigateRecord(-1) }
  navigateNext() { this.#navigateRecord(1) }

  #navigateRecord(direction) {
    const newIndex = this.currentIndex + direction
    if (newIndex >= 0 && newIndex < this.currentData.length) {
      this.currentIndex = newIndex
      this.#displayRecord(this.currentIndex)
      this.recordSelectorTarget.value = this.currentIndex
    }
  }

  selectRecord(event) {
    this.currentIndex = Number.parseInt(event.target.value)
    this.#displayRecord(this.currentIndex)
  }

  // --- Save -------------------------------------------------------------

  async saveCurrentRecord() {
    if (!this.currentDocumentId) {
      this.#showNotification("No document loaded", "error")
      return
    }

    const record = this.currentData[this.currentIndex]
    const updates = {}

    // Collect updated field values
    const textareas = this.tableBodyTarget.querySelectorAll("textarea")
    textareas.forEach((textarea) => {
      const fieldName = textarea.dataset.field
      updates[fieldName] = textarea.value
    })

    try {
      const payload = {
        controls: {
          [record.control_id]: updates
        }
      }

      const response = await fetch(
        `${this.apiBaseUrlValue}/ssp_documents/${this.currentDocumentId}/update_fields`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": this.#csrfToken
          },
          body: JSON.stringify(payload)
        }
      )

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || "Update failed")
      }

      await response.json()

      // Update local data
      record.fields.forEach((field) => {
        if (updates[field.field_name] !== undefined) {
          field.field_value = updates[field.field_name]
        }
      })

      this.#showNotification("✅ Control saved successfully!", "success")
    } catch (error) {
      console.error("Save error:", error)
      this.#showNotification(`❌ Error saving: ${error.message}`, "error")
    }
  }

  async saveAllRecords() {
    if (!this.currentDocumentId) {
      this.#showNotification("No document loaded", "error")
      return
    }

    try {
      // Collect all updates
      const allUpdates = {}

      this.currentData.forEach((record) => {
        const updates = {}
        record.fields.forEach((field) => {
          if (field.editable) {
            updates[field.field_name] = field.field_value
          }
        })
        allUpdates[record.control_id] = updates
      })

      const response = await fetch(
        `${this.apiBaseUrlValue}/ssp_documents/${this.currentDocumentId}/update_fields`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": this.#csrfToken
          },
          body: JSON.stringify({ controls: allUpdates })
        }
      )

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || "Update failed")
      }

      this.#showNotification("✅ All controls saved successfully!", "success")
    } catch (error) {
      console.error("Save error:", error)
      this.#showNotification(`❌ Error saving: ${error.message}`, "error")
    }
  }

  resetCurrentRecord() {
    this.#displayRecord(this.currentIndex)
    this.#showNotification("Record reset to original values", "info")
  }

  // --- Export -----------------------------------------------------------

  exportJSON() {
    if (!this.currentDocumentId) {
      this.#showNotification("No document loaded", "error")
      return
    }

    try {
      window.location.href =
        this.downloadPathValue.replace("__ID__", this.currentDocumentId)
      this.#showNotification("✅ Export started!", "success")
    } catch (error) {
      console.error("Export error:", error)
      this.#showNotification(`❌ Error exporting: ${error.message}`, "error")
    }
  }

  // --- UI helpers -------------------------------------------------------

  #showEditorUI() {
    this.navigationContainerTarget.style.display = "block"
    this.legendTarget.style.display = "flex"
    this.headerInfoTarget.style.display = "block"
    this.dataTableTarget.style.display = "table"
    this.actionButtonsTarget.style.display = "flex"
  }

  #showNotification(message, type) {
    const notification = this.notificationTarget
    notification.textContent = message
    notification.className = `notification ${type}`
    notification.style.display = "block"

    setTimeout(() => {
      notification.style.display = "none"
    }, 5000)
  }
}
