import { Controller } from "@hotwired/stimulus"

/**
 * Drag-and-drop file upload controller.
 *
 * Wraps a hidden <input type="file"> with a visual drop zone that supports
 * drag-over feedback, click-to-browse, file type validation, and size limits.
 * Supports both single-file and multi-file modes.
 *
 * Usage (via shared/_dropzone.html.erb partial):
 *   <div data-controller="dropzone"
 *        data-dropzone-accept-value=".xml,.json"
 *        data-dropzone-multiple-value="true"
 *        data-dropzone-max-size-value="52428800">
 *     ...
 *   </div>
 */
export default class DropzoneController extends Controller {
  static targets = ["input", "zone", "filename", "error", "prompt", "icon", "filesize", "fileList"]
  static values = {
    accept: { type: String, default: "" },
    maxSize: { type: Number, default: 52428800 }, // 50 MB
    multiple: { type: Boolean, default: false },
    required: { type: Boolean, default: false }
  }

  connect() {
    this.dragCounter = 0
    this.selectedFiles = [] // Track files for multi-mode

    // #902 — the file input is `d-none`, so the native `required` attribute
    // cannot be used: Chrome blocks submission of a form with a required
    // control it cannot focus and reports it only to the console, leaving the
    // user staring at a button that appears to do nothing. Enforce it here
    // instead, where the message can actually be shown.
    this.form = this.element.closest("form")
    if (this.form) {
      this.onSubmit = this.validateOnSubmit.bind(this)
      // Capture phase: run before Turbo's submit handling, so preventDefault
      // stops the request being made at all.
      this.form.addEventListener("submit", this.onSubmit, { capture: true })
    }
  }

  disconnect() {
    if (this.form && this.onSubmit) {
      this.form.removeEventListener("submit", this.onSubmit, { capture: true })
    }
  }

  // ── Submit-time guard ────────────────────────────────────────────

  validateOnSubmit(event) {
    if (!this.requiredValue) return
    if (this.inputTarget.files && this.inputTarget.files.length > 0) return

    event.preventDefault()
    event.stopPropagation()

    this.showError(
      this.multipleValue
        ? "Select at least one file before submitting."
        : "Select a file before submitting."
    )

    // Move focus to the zone so the message is announced and the user is put
    // where the problem is, mirroring what native validation would have done.
    this.zoneTarget.setAttribute("tabindex", "-1")
    this.zoneTarget.focus()
    this.zoneTarget.scrollIntoView({ block: "center", behavior: "smooth" })
  }

  // ── Drag events ──────────────────────────────────────────────────

  dragover(event) {
    event.preventDefault()
    event.stopPropagation()
    event.dataTransfer.dropEffect = "copy"
  }

  dragenter(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter++
    this.zoneTarget.classList.add("sparc-dropzone--dragover")
  }

  dragleave(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter--
    if (this.dragCounter <= 0) {
      this.dragCounter = 0
      this.zoneTarget.classList.remove("sparc-dropzone--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    event.stopPropagation()
    this.dragCounter = 0
    this.zoneTarget.classList.remove("sparc-dropzone--dragover")

    const files = event.dataTransfer.files
    if (files.length === 0) return

    if (this.multipleValue) {
      this.handleMultipleFiles(files)
    } else {
      this.handleFile(files[0], files)
    }
  }

  // ── Click-to-browse ──────────────────────────────────────────────

  browse(event) {
    if (event.target === this.inputTarget) return
    // Don't trigger browse when clicking remove buttons in file list
    if (event.target.closest(".sparc-dropzone__remove-btn")) return
    event.preventDefault()
    this.inputTarget.click()
  }

  // ── File input change (from browse dialog) ───────────────────────

  change(event) {
    const files = event.target.files
    if (files.length === 0) return

    if (this.multipleValue) {
      this.handleMultipleFiles(files)
    } else {
      this.handleFile(files[0])
    }
  }

  // ── Single-file handler (existing behavior) ──────────────────────

  handleFile(file, dataTransferFiles) {
    this.clearState()

    if (!this.validateFile(file)) {
      // #902 — a file chosen through the browse dialog is already on the input
      // by the time we see it. Leaving a client-rejected file there means the
      // form posts it anyway and the user is told "no" a second time, by the
      // server, after the upload. Drop it so the rejection is final here.
      this.inputTarget.value = ""
      return
    }

    if (dataTransferFiles) {
      this.inputTarget.files = dataTransferFiles
    }

    this.zoneTarget.classList.add("sparc-dropzone--has-file")
    this.filenameTarget.textContent = file.name
    if (this.hasFilesizeTarget) {
      this.filesizeTarget.textContent = this.formatSize(file.size)
    }

    this.dispatch("fileSelected", { detail: { file } })
  }

  // ── Multi-file handler ───────────────────────────────────────────

  handleMultipleFiles(fileList) {
    this.clearState()

    const accepted = []
    const rejected = []

    for (const file of fileList) {
      if (this.validateFile(file, false)) {
        accepted.push(file)
      } else {
        rejected.push(file)
      }
    }

    if (accepted.length === 0) {
      this.inputTarget.value = ""
      this.showError("No valid files found. Check file types and sizes.")
      return
    }

    // Merge with existing selections (allow multiple drops)
    for (const file of accepted) {
      // Avoid duplicates by name + size
      const exists = this.selectedFiles.some(f => f.name === file.name && f.size === file.size)
      if (!exists) {
        this.selectedFiles.push(file)
      }
    }

    // Update the hidden input with all selected files
    this.syncInputFiles()

    // Show file list UI
    this.renderFileList()

    // Show rejection warnings
    if (rejected.length > 0) {
      const names = rejected.map(f => f.name).join(", ")
      this.showError(`${rejected.length} file(s) rejected: ${names}`)
    }

    this.dispatch("filesSelected", { detail: { files: this.selectedFiles } })
  }

  // ── File list rendering ──────────────────────────────────────────

  renderFileList() {
    if (!this.hasFileListTarget) return

    this.zoneTarget.classList.add("sparc-dropzone--has-file")
    this.fileListTarget.style.display = "block"
    this.filenameTarget.textContent = ""
    if (this.hasFilesizeTarget) {
      this.filesizeTarget.textContent = ""
    }

    // Build file list HTML
    const totalSize = this.selectedFiles.reduce((sum, f) => sum + f.size, 0)
    let html = `<div class="sparc-dropzone__file-summary">${this.selectedFiles.length} file(s) selected &mdash; ${this.formatSize(totalSize)}</div>`

    this.selectedFiles.forEach((file, index) => {
      html += `
        <div class="sparc-dropzone__file-row" data-index="${index}">
          <span class="sparc-dropzone__file-name">${this.escapeHtml(file.name)}</span>
          <span class="sparc-dropzone__file-size">${this.formatSize(file.size)}</span>
          <button type="button" class="sparc-dropzone__remove-btn" data-action="click->dropzone#removeFile" data-index="${index}" title="Remove">&times;</button>
        </div>`
    })

    this.fileListTarget.innerHTML = html
  }

  removeFile(event) {
    event.preventDefault()
    event.stopPropagation()
    const index = Number.parseInt(event.currentTarget.dataset.index)
    this.selectedFiles.splice(index, 1)

    if (this.selectedFiles.length === 0) {
      this.clearState()
      return
    }

    this.syncInputFiles()
    this.renderFileList()
    this.dispatch("filesSelected", { detail: { files: this.selectedFiles } })
  }

  // ── Validation ───────────────────────────────────────────────────

  validateFile(file, showError = true) {
    // Validate extension
    if (this.acceptValue) {
      const allowed = this.acceptValue.split(",").map(e => e.trim().toLowerCase())
      const ext = "." + file.name.split(".").pop().toLowerCase()
      if (!allowed.includes(ext)) {
        if (showError) this.showError(`Invalid file type "${ext}". Accepted: ${this.acceptValue}`)
        return false
      }
    }

    // Validate size
    if (file.size > this.maxSizeValue) {
      const maxMB = (this.maxSizeValue / 1048576).toFixed(0)
      if (showError) this.showError(`File too large (${this.formatSize(file.size)}). Maximum: ${maxMB} MB.`)
      return false
    }

    return true
  }

  // ── Sync selected files to the hidden input ──────────────────────

  syncInputFiles() {
    const dataTransfer = new DataTransfer()
    this.selectedFiles.forEach(file => dataTransfer.items.add(file))
    this.inputTarget.files = dataTransfer.files
  }

  // ── Helpers ──────────────────────────────────────────────────────

  clearState() {
    this.selectedFiles = []
    this.zoneTarget.classList.remove(
      "sparc-dropzone--has-file",
      "sparc-dropzone--error",
      "sparc-dropzone--dragover"
    )
    this.filenameTarget.textContent = ""
    this.errorTarget.textContent = ""
    if (this.hasFilesizeTarget) {
      this.filesizeTarget.textContent = ""
    }
    if (this.hasFileListTarget) {
      this.fileListTarget.innerHTML = ""
      this.fileListTarget.style.display = "none"
    }
  }

  showError(message) {
    this.zoneTarget.classList.add("sparc-dropzone--error")
    this.errorTarget.textContent = message
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`
    return `${(bytes / 1048576).toFixed(1)} MB`
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
