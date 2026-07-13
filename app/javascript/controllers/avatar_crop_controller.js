import { Controller } from "@hotwired/stimulus"
import Cropper from "cropperjs"

// Avatar crop/scale/center controller for profile page.
// Uses Cropper.js for client-side image manipulation before upload.
//
// NIST SP 800-53 SI-10: Validates file type and size client-side
// before allowing crop. Server-side validation in User model.
export default class AvatarCropController extends Controller {
  static targets = ["input", "cropImage", "preview", "modal", "slider", "form", "dropzone", "currentAvatar"]
  static values = { maxSize: { type: Number, default: 2097152 } } // 2MB

  connect() {
    this.cropper = null
    this.acceptedTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
  }

  disconnect() {
    this.destroyCropper()
  }

  // --- File Selection ---

  selectFile() {
    this.inputTarget.click()
  }

  fileSelected(event) {
    const file = event.target.files[0]
    if (file) this.handleFile(file)
  }

  // --- Drag & Drop ---

  dragOver(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.add("sparc-dropzone--dragover")
  }

  dragLeave(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("sparc-dropzone--dragover")
  }

  drop(event) {
    event.preventDefault()
    this.dropzoneTarget.classList.remove("sparc-dropzone--dragover")
    const file = event.dataTransfer.files[0]
    if (file) this.handleFile(file)
  }

  // --- File Validation (SI-10) ---

  handleFile(file) {
    // Validate type
    if (!this.acceptedTypes.includes(file.type)) {
      this.showError("Please select a PNG, JPG, GIF, or WebP image.")
      return
    }

    // Validate size
    if (file.size > this.maxSizeValue) {
      this.showError("Image must be less than 2 MB.")
      return
    }

    this.clearError()
    this.openCropModal(file)
  }

  // --- Crop Modal ---

  openCropModal(file) {
    const reader = new FileReader()
    reader.onload = (e) => {
      this.cropImageTarget.src = e.target.result
      this.showModal()
      // Wait for image to load before initializing cropper
      this.cropImageTarget.onload = () => {
        this.initCropper()
      }
    }
    reader.readAsDataURL(file)
  }

  initCropper() {
    this.destroyCropper()

    this.cropper = new Cropper(this.cropImageTarget, {
      aspectRatio: 1,
      viewMode: 1,
      dragMode: "move",
      autoCropArea: 1,
      cropBoxResizable: false,
      cropBoxMovable: false,
      guides: false,
      center: true,
      highlight: false,
      background: false,
      responsive: true,
      ready: () => {
        this.updatePreview()
      },
      crop: () => {
        this.updatePreview()
      }
    })

    // Set initial slider value
    if (this.hasSliderTarget) {
      this.sliderTarget.value = 0
    }
  }

  destroyCropper() {
    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  }

  // --- Controls ---

  zoom(event) {
    if (!this.cropper) return
    const value = Number.parseFloat(event.target.value)
    // Map slider 0-100 to zoom ratio 0-2
    const ratio = value / 50
    this.cropper.zoomTo(ratio)
  }

  // --- Preview ---

  updatePreview() {
    if (!this.cropper || !this.hasPreviewTarget) return

    try {
      const canvas = this.cropper.getCroppedCanvas({
        width: 128,
        height: 128,
        imageSmoothingEnabled: true,
        imageSmoothingQuality: "high"
      })
      if (canvas) {
        this.previewTarget.src = canvas.toDataURL("image/png")
      }
    } catch {
      // Ignore cross-origin or timing errors
    }
  }

  // --- Save ---

  saveCrop() {
    if (!this.cropper) return

    const canvas = this.cropper.getCroppedCanvas({
      width: 256,
      height: 256,
      imageSmoothingEnabled: true,
      imageSmoothingQuality: "high"
    })

    canvas.toBlob((blob) => {
      // Create a File from the blob
      const file = new File([blob], "avatar.png", { type: "image/png" })

      // Create a DataTransfer to set the file input
      const dataTransfer = new DataTransfer()
      dataTransfer.items.add(file)
      this.inputTarget.files = dataTransfer.files

      // Submit the form
      this.hideModal()
      this.formTarget.requestSubmit()
    }, "image/png", 0.95)
  }

  cancelCrop() {
    this.destroyCropper()
    this.hideModal()
    // Clear the file input
    this.inputTarget.value = ""
  }

  // --- Modal Helpers ---

  showModal() {
    const modal = new bootstrap.Modal(this.modalTarget)
    modal.show()
  }

  hideModal() {
    const modal = bootstrap.Modal.getInstance(this.modalTarget)
    if (modal) modal.hide()
    this.destroyCropper()
  }

  // --- Error Display ---

  showError(message) {
    this.dropzoneTarget.classList.add("sparc-dropzone--error")
    const errorEl = this.dropzoneTarget.querySelector("[data-error]")
    if (errorEl) {
      errorEl.textContent = message
      errorEl.classList.remove("d-none")
    }
  }

  clearError() {
    this.dropzoneTarget.classList.remove("sparc-dropzone--error")
    const errorEl = this.dropzoneTarget.querySelector("[data-error]")
    if (errorEl) {
      errorEl.textContent = ""
      errorEl.classList.add("d-none")
    }
  }
}
