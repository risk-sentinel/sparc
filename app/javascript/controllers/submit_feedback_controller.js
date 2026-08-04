import { Controller } from "@hotwired/stimulus"

/**
 * Makes failed form submissions visible (#902).
 *
 * Turbo handles a form response by rendering it. That works when the response
 * comes from Rails, but not when the request never gets there:
 *
 *   - The edge WAF blocked the POST (sparc-iac#620 — an evidence upload was
 *     blocked by `CrossSiteScripting_BODY` and never reached the app, so no
 *     controller ran, no flash was set, and the user saw nothing happen).
 *   - A reverse proxy rejected the body size (413) before Rails saw it.
 *   - The request failed in transport entirely — offline, DNS, TLS, timeout.
 *
 * In those cases Turbo has either no body to render or an unbranded error
 * document from the edge, and the user is left guessing whether their work
 * was saved. For compliance evidence that is the worst possible outcome: an
 * assessor believing an artefact is on file when it is not.
 *
 * Scope is deliberately narrow — form submissions only, and only for statuses
 * Rails does not already handle meaningfully:
 *
 *   - 2xx / 3xx        → untouched, normal Turbo flow.
 *   - 422              → untouched. This is the Rails validation contract; the
 *                        re-rendered form carries its own inline field errors.
 *   - everything else  → the render is cancelled and a persistent error flash
 *                        is shown, which keeps the user's filled-in form on
 *                        screen so they can retry without retyping.
 *
 * Link navigations are not intercepted: a 404 or 500 during a visit should
 * still render its error page, and there is no user input at risk.
 */
export default class SubmitFeedbackController extends Controller {
  // Rails' own validation-failure status. Its response body IS the feedback.
  static VALIDATION_STATUS = 422

  connect() {
    this.onBeforeFetchResponse = this.handleResponse.bind(this)
    this.onRequestError = this.handleTransportError.bind(this)

    document.addEventListener("turbo:before-fetch-response", this.onBeforeFetchResponse)
    document.addEventListener("turbo:fetch-request-error", this.onRequestError)
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-response", this.onBeforeFetchResponse)
    document.removeEventListener("turbo:fetch-request-error", this.onRequestError)
  }

  // ── Handlers ─────────────────────────────────────────────────────

  handleResponse(event) {
    if (!this.isFormSubmission(event)) return

    const response = event.detail?.fetchResponse?.response
    if (!response || response.ok) return
    if (response.status === this.constructor.VALIDATION_STATUS) return

    // Stop Turbo replacing the page with the edge's error document. The user's
    // input stays on screen, and the message below explains what happened.
    event.preventDefault()
    this.report(this.messageForStatus(response.status))
  }

  handleTransportError(event) {
    if (!this.isFormSubmission(event)) return

    this.report(
      "Your submission did not reach SPARC — the connection failed. " +
      "Nothing was saved. Check your network and try again; your entries have been kept."
    )
  }

  // Turbo dispatches form-submission fetch events on the <form> itself, and
  // visit events on the document element or a turbo-frame.
  isFormSubmission(event) {
    return event.target instanceof HTMLFormElement
  }

  // ── Messages ─────────────────────────────────────────────────────

  //
  // Deliberately does not claim "nothing was saved" for server errors: a 500
  // can happen after a partial write, and telling someone their evidence was
  // definitely not stored when it might have been is the same class of mistake
  // as telling them it was. Say what is known.
  //
  messageForStatus(status) {
    const kept = "Your entries have been kept so you can retry."

    if (status === 403 || status === 401) {
      return (
        `Your submission was blocked before it reached SPARC (HTTP ${status}). ` +
        `Nothing was saved. This is usually a network security policy rejecting ` +
        `the request — if it keeps happening, contact your administrator. ${kept}`
      )
    }

    if (status === 413) {
      return (
        `Your submission was rejected as too large (HTTP 413) before it reached ` +
        `SPARC. Nothing was saved. Try a smaller file. ${kept}`
      )
    }

    if (status >= 500) {
      return (
        `SPARC could not process your submission (HTTP ${status}). ` +
        `It was not confirmed as saved — check before retrying to avoid a ` +
        `duplicate. ${kept}`
      )
    }

    return (
      `Your submission failed (HTTP ${status}) and was not confirmed as saved. ${kept}`
    )
  }

  // ── Rendering ────────────────────────────────────────────────────

  // Builds the same markup the layout emits for a server-side flash, so this
  // message looks identical to every other error and is managed by the same
  // flash controller — which means it persists until dismissed.
  report(message) {
    const container = this.flashContainer()

    const alert = document.createElement("div")
    alert.className = "alert alert-danger alert-dismissible fade show flash"
    alert.setAttribute("data-flash-target", "message")
    alert.setAttribute("data-flash-key", "error")
    alert.setAttribute("role", "alert")
    alert.setAttribute("aria-live", "assertive")
    alert.textContent = message

    const close = document.createElement("button")
    close.type = "button"
    close.className = "btn-close"
    close.setAttribute("data-action", "click->flash#dismiss")
    close.setAttribute("aria-label", "Dismiss error")

    alert.appendChild(close)
    container.appendChild(alert)
  }

  flashContainer() {
    const existing = document.querySelector(".flash-container")
    if (existing) return existing

    const container = document.createElement("div")
    container.className = "flash-container"
    container.setAttribute("data-controller", "flash")
    document.body.appendChild(container)
    return container
  }
}
