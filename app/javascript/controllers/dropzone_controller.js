import { Controller } from "@hotwired/stimulus"

/**
 * Drag-and-drop file upload controller.
 *
 * Wraps a hidden <input type="file"> with a visual drop zone that supports
 * drag-over feedback, click-to-browse, file type validation, and size limits.
 *
 * Usage (via shared/_dropzone.html.erb partial):
 *   <div data-controller="dropzone"
 *        data-dropzone-accept-value=".xml,.json"
 *        data-dropzone-max-size-value="52428800">
 *     ...
 *   </div>
 */
export default class extends Controller {
  static targets = ["input", "zone", "filename", "error", "prompt", "icon", "filesize"]
  static values = {
    accept: { type: String, default: "" },
    maxSize: { type: Number, default: 52428800 } // 50 MB
  }

  connect() {
    // Bind zone-level drag events (prevent page-level drag from interfering)
    this.dragCounter = 0
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

    this.handleFile(files[0], files)
  }

  // ── Click-to-browse ──────────────────────────────────────────────

  browse(event) {
    // Only trigger browse if the click was on the drop zone itself,
    // not on the hidden input (which would cause a double-trigger).
    if (event.target === this.inputTarget) return
    event.preventDefault()
    this.inputTarget.click()
  }

  // ── File input change (from browse dialog) ───────────────────────

  change(event) {
    const files = event.target.files
    if (files.length === 0) return
    this.handleFile(files[0])
  }

  // ── Core file handler ────────────────────────────────────────────

  handleFile(file, dataTransferFiles) {
    this.clearState()

    // Validate extension
    if (this.acceptValue) {
      const allowed = this.acceptValue.split(",").map(e => e.trim().toLowerCase())
      const ext = "." + file.name.split(".").pop().toLowerCase()
      if (!allowed.includes(ext)) {
        this.showError(`Invalid file type "${ext}". Accepted: ${this.acceptValue}`)
        return
      }
    }

    // Validate size
    if (file.size > this.maxSizeValue) {
      const maxMB = (this.maxSizeValue / 1048576).toFixed(0)
      this.showError(`File too large (${this.formatSize(file.size)}). Maximum: ${maxMB} MB.`)
      return
    }

    // Assign file to the hidden input (for drag-and-drop cases)
    if (dataTransferFiles) {
      this.inputTarget.files = dataTransferFiles
    }

    // Show success state
    this.zoneTarget.classList.add("sparc-dropzone--has-file")
    this.filenameTarget.textContent = file.name
    if (this.hasFilesizeTarget) {
      this.filesizeTarget.textContent = this.formatSize(file.size)
    }

    // Dispatch custom event for other controllers to hook into
    this.dispatch("fileSelected", { detail: { file } })
  }

  // ── Helpers ──────────────────────────────────────────────────────

  clearState() {
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
}
