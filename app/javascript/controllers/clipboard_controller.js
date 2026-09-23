import { Controller } from "@hotwired/stimulus"

// Copies a value to the device clipboard (#1180).
//
// Stimulus rather than an onclick: the enforced CSP forbids inline `on*=`
// handlers and unnonced <script>, and Turbo Drive strips the nonce from any
// inline script it clones on navigation (#712 / #528). A copy button is also
// the shape of bug that renders fine and only fails on click, so it is wired
// the way every other interactive control here is.
//
// TWO CLIPBOARD PATHS, DELIBERATELY. `navigator.clipboard` is only defined in a
// SECURE CONTEXT. SPARC is deployed behind TLS postures we do not control, and
// on a plain-http instance the modern API is simply `undefined` — the button
// would do nothing, silently. `document.execCommand("copy")` is deprecated but
// still works there, so it is the fallback, and a failure of both is REPORTED
// rather than swallowed.
export default class ClipboardController extends Controller {
  static targets = ["icon", "check", "status"]
  static values = {
    text: String,
    // How long the confirmation shows, ms.
    confirmFor: { type: Number, default: 1600 },
  }

  disconnect() {
    // Turbo swaps the page out from under us; a pending timer would fire
    // against detached nodes.
    if (this.timer) clearTimeout(this.timer)
  }

  async copy(event) {
    event.preventDefault()

    const text = this.textValue
    if (!text) return

    let ok = false
    if (navigator.clipboard && window.isSecureContext) {
      try {
        await navigator.clipboard.writeText(text)
        ok = true
      } catch {
        ok = false
      }
    }
    if (!ok) ok = this.#copyViaExecCommand(text)

    this.#confirm(ok)
  }

  // Insecure-context fallback. The textarea is off-screen rather than
  // `display:none` — a hidden element cannot be selected, so the copy would
  // report success having copied nothing.
  #copyViaExecCommand(text) {
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.top = "-1000px"
    document.body.appendChild(area)
    area.select()

    let ok = false
    try {
      ok = document.execCommand("copy")
    } catch {
      ok = false
    } finally {
      area.remove()
    }
    return ok
  }

  #confirm(ok) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = ok ? "Copied to clipboard" : "Copy failed"
    }
    if (ok && this.hasIconTarget && this.hasCheckTarget) {
      this.iconTarget.classList.add("d-none")
      this.checkTarget.classList.remove("d-none")
    }
    this.element.classList.toggle("sparc-uuid--copied", ok)
    this.element.classList.toggle("sparc-uuid--failed", !ok)

    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.#reset(), this.confirmForValue)
  }

  #reset() {
    if (this.hasIconTarget && this.hasCheckTarget) {
      this.iconTarget.classList.remove("d-none")
      this.checkTarget.classList.add("d-none")
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
    this.element.classList.remove("sparc-uuid--copied", "sparc-uuid--failed")
  }
}
