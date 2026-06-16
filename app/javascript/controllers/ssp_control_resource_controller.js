import { Controller } from "@hotwired/stimulus"

// Per-control back-matter resource linking on the SSP show page (#647, #650).
// Replaces inline onclick handlers (toggleSspAddRef / createSspControlResource /
// unlinkSspControlResource) and a nonce'd <script> of globals that strict CSP
// (script-src :self, no 'unsafe-inline') silently blocked, leaving the
// add-reference / unlink controls inert.
//
// Endpoint URLs come from data-*-value attributes (server-generated routes),
// never interpolated into executable JS. DOM ids preserved from the originals.
export default class extends Controller {
  static values = { createUrl: String, unlinkUrl: String }

  // Show/hide the inline "add reference" form for a control row.
  toggleAddRef(event) {
    const id = event.params.id
    const form = document.getElementById(`ssp-add-ref-${id}`)
    const btn = document.getElementById(`ssp-add-ref-btn-${id}`)
    if (!form || !btn) return
    const visible = form.style.display !== "none"
    form.style.display = visible ? "none" : ""
    btn.style.display = visible ? "" : "none"
    if (!visible) {
      const title = document.getElementById(`ssp-ref-title-${id}`)
      if (title) title.focus()
    }
  }

  create(event) {
    const { controlId, dbId } = event.params
    const title = document.getElementById(`ssp-ref-title-${dbId}`).value.trim()
    if (!title) { alert("Title is required"); return }
    const href = document.getElementById(`ssp-ref-href-${dbId}`).value.trim()
    const mediaType = document.getElementById(`ssp-ref-media-${dbId}`).value.trim()

    fetch(this.createUrlValue, {
      method: "POST",
      headers: this.#headers(),
      body: JSON.stringify({
        control_id: controlId,
        back_matter_resource: { title, href, media_type: mediaType }
      })
    })
      .then((resp) => resp.json())
      .then((data) => {
        if (data.success) { location.reload() }
        else { alert("Error: " + (data.error || "Unknown error")) }
      })
      .catch((err) => { alert("Failed: " + err.message) })
  }

  unlink(event) {
    const { controlId, linkId } = event.params
    if (!confirm("Unlink this resource?")) return

    fetch(this.unlinkUrlValue, {
      method: "DELETE",
      headers: this.#headers(),
      body: JSON.stringify({ control_id: controlId, link_id: linkId })
    })
      .then((resp) => resp.json())
      .then((data) => {
        if (data.success) { location.reload() }
        else { alert("Error: " + (data.error || "Unknown error")) }
      })
      .catch((err) => { alert("Failed: " + err.message) })
  }

  #headers() {
    return {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      "Accept": "application/json"
    }
  }
}
