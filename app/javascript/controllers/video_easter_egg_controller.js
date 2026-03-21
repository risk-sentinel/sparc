import { Controller } from "@hotwired/stimulus"

// Easter egg: clicking the SPARC navbar logo plays an intro video
// in a fullscreen dark overlay. Dismisses on Escape, click outside
// the video, or when the video ends naturally.
//
// Usage (in layout):
//   <div data-controller="video-easter-egg">
//     <a data-action="click->video-easter-egg#play">Logo</a>
//   </div>
//   ...
//   <div class="sparc-video-overlay d-none"
//        data-video-easter-egg-target="overlay"
//        data-action="click->video-easter-egg#overlayClick">
//     <video data-video-easter-egg-target="video"
//            data-action="ended->video-easter-egg#videoEnded"
//            preload="none">
//       <source src="/videos/sparc_intro.mp4" type="video/mp4">
//     </video>
//   </div>
export default class extends Controller {
  static targets = ["overlay", "video"]

  play(event) {
    event.preventDefault()
    if (!this.hasOverlayTarget || !this.hasVideoTarget) return

    this.overlayTarget.classList.remove("d-none")
    this.videoTarget.currentTime = 0
    this.videoTarget.play()
    this._boundKeyHandler = this._handleKey.bind(this)
    document.addEventListener("keydown", this._boundKeyHandler)
  }

  dismiss() {
    if (!this.hasVideoTarget) return
    this.videoTarget.pause()
    this.overlayTarget.classList.add("d-none")
    this._removeKeyHandler()
  }

  overlayClick(event) {
    // Only dismiss when clicking the backdrop, not the video itself
    if (event.target === this.overlayTarget) {
      this.dismiss()
    }
  }

  videoEnded() {
    this.dismiss()
  }

  disconnect() {
    this._removeKeyHandler()
  }

  // Private

  _handleKey(event) {
    if (event.key === "Escape") this.dismiss()
  }

  _removeKeyHandler() {
    if (this._boundKeyHandler) {
      document.removeEventListener("keydown", this._boundKeyHandler)
      this._boundKeyHandler = null
    }
  }
}
