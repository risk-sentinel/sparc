import { Controller } from "@hotwired/stimulus"

// FIDO2/WebAuthn security-key enrollment (#779). Drives the browser's native
// navigator.credentials.create ceremony against WebauthnCredentialsController.
// No inline JS — wired via data-action (CSP has no 'unsafe-inline'). The browser
// speaks binary (ArrayBuffer); the server speaks base64url, so we translate at
// the boundary.
export default class extends Controller {
  static targets = ["nickname", "status", "submit", "email"]
  static values = {
    optionsUrl: String, createUrl: String,       // enrollment
    authOptionsUrl: String, authUrl: String       // sign-in
  }

  async register(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      this.setStatus("This browser does not support security keys.", "danger")
      return
    }

    this.submitTarget.disabled = true
    this.setStatus("Touch your security key and enter its PIN when prompted…", "info")

    try {
      const options = await this.postJSON(this.optionsUrlValue)
      const credential = await navigator.credentials.create({
        publicKey: this.decodeCreationOptions(options)
      })

      const result = await this.postJSON(this.createUrlValue, {
        credential: this.encodeCredential(credential),
        nickname: this.hasNicknameTarget ? this.nicknameTarget.value : ""
      })
      if (result.error) throw new Error(result.error)

      this.setStatus("Security key added.", "success")
      window.location.reload()
    } catch (error) {
      this.submitTarget.disabled = false
      this.setStatus(this.friendlyError(error), "danger")
    }
  }

  // Passwordless sign-in: the security key + PIN is the login.
  async login(event) {
    event.preventDefault()

    if (!window.PublicKeyCredential) {
      this.setStatus("This browser does not support security keys.", "danger")
      return
    }

    this.submitTarget.disabled = true
    this.setStatus("Touch your security key and enter its PIN when prompted…", "info")

    try {
      const email = this.hasEmailTarget ? this.emailTarget.value : ""
      const options = await this.postJSON(this.authOptionsUrlValue, email ? { email } : null)
      const assertion = await navigator.credentials.get({
        publicKey: this.decodeRequestOptions(options)
      })

      const result = await this.postJSON(this.authUrlValue, { credential: this.encodeAssertion(assertion) })
      if (result.error) throw new Error(result.error)

      window.location.assign(result.redirect_to || "/")
    } catch (error) {
      this.submitTarget.disabled = false
      this.setStatus(this.friendlyError(error), "danger")
    }
  }

  // ── ceremony translation ────────────────────────────────────────────────

  decodeCreationOptions(options) {
    const publicKey = { ...options }
    publicKey.challenge = this.base64urlToBuffer(options.challenge)
    publicKey.user = { ...options.user, id: this.base64urlToBuffer(options.user.id) }
    if (Array.isArray(options.excludeCredentials)) {
      publicKey.excludeCredentials = options.excludeCredentials.map((c) => ({
        ...c,
        id: this.base64urlToBuffer(c.id)
      }))
    }
    return publicKey
  }

  decodeRequestOptions(options) {
    const publicKey = { ...options }
    publicKey.challenge = this.base64urlToBuffer(options.challenge)
    if (Array.isArray(options.allowCredentials)) {
      publicKey.allowCredentials = options.allowCredentials.map((c) => ({
        ...c,
        id: this.base64urlToBuffer(c.id)
      }))
    }
    return publicKey
  }

  encodeAssertion(assertion) {
    return {
      type: assertion.type,
      id: assertion.id,
      rawId: this.bufferToBase64url(assertion.rawId),
      clientExtensionResults: assertion.getClientExtensionResults?.() ?? {},
      response: {
        authenticatorData: this.bufferToBase64url(assertion.response.authenticatorData),
        clientDataJSON: this.bufferToBase64url(assertion.response.clientDataJSON),
        signature: this.bufferToBase64url(assertion.response.signature),
        userHandle: assertion.response.userHandle ? this.bufferToBase64url(assertion.response.userHandle) : null
      }
    }
  }

  encodeCredential(credential) {
    return {
      type: credential.type,
      id: credential.id,
      rawId: this.bufferToBase64url(credential.rawId),
      authenticatorAttachment: credential.authenticatorAttachment,
      clientExtensionResults: credential.getClientExtensionResults?.() ?? {},
      response: {
        attestationObject: this.bufferToBase64url(credential.response.attestationObject),
        clientDataJSON: this.bufferToBase64url(credential.response.clientDataJSON)
      }
    }
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  async postJSON(url, body) {
    const response = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content
      },
      body: body ? JSON.stringify(body) : null
    })
    const data = await response.json().catch(() => ({}))
    if (!response.ok && data.error) throw new Error(data.error)
    return data
  }

  friendlyError(error) {
    if (error.name === "NotAllowedError") return "Enrollment was cancelled or timed out. Please try again."
    if (error.name === "InvalidStateError") return "This security key is already registered."
    return error.message || "Could not add the security key."
  }

  setStatus(message, variant) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.className = `alert alert-${variant} mt-3`
    this.statusTarget.hidden = false
  }

  base64urlToBuffer(value) {
    const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=")
    const binary = atob(base64)
    const bytes = new Uint8Array(binary.length)
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
    return bytes.buffer
  }

  bufferToBase64url(buffer) {
    const bytes = new Uint8Array(buffer)
    let binary = ""
    for (const byte of bytes) binary += String.fromCharCode(byte)
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }
}
