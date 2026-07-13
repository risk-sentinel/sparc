import { Controller } from "@hotwired/stimulus"

// Inline field editing + per-control back-matter resource linking on the CDEF
// show page (#647, epic #650). Replaces inline onclick handlers (toggleFieldEdit
// / saveField / toggleAddRef / createControlResource / unlinkControlResource) and
// a nonce'd <script> of globals that strict CSP (script-src :self, no
// 'unsafe-inline') silently blocked, leaving inline edit + add-reference inert.
//
// Endpoint URLs come from data-*-value attributes (server-generated routes),
// never interpolated into executable JS. DOM ids preserved from the originals.
export default class CdefControlController extends Controller {
  static values = { updateFieldUrl: String, createUrl: String, unlinkUrl: String }

  // ── Inline field editing ──────────────────────────────────────────────
  toggleFieldEdit(event) {
    const { controlId, fieldName } = event.params
    const display = document.getElementById(`field-display-${controlId}-${fieldName}`)
    const edit = document.getElementById(`field-edit-${controlId}-${fieldName}`)
    if (!edit) return
    const editing = edit.style.display !== "none"
    display.style.display = editing ? "" : "none"
    edit.style.display = editing ? "none" : ""
    if (!editing) {
      const input = document.getElementById(`field-input-${controlId}-${fieldName}`)
      if (input) input.focus()
    }
  }

  saveField(event) {
    const { controlId, fieldName } = event.params
    const input = document.getElementById(`field-input-${controlId}-${fieldName}`)
    if (!input) return
    const value = input.value

    fetch(this.updateFieldUrlValue, {
      method: "PATCH",
      headers: this.#headers(),
      body: JSON.stringify({ control_id: controlId, field_name: fieldName, field_value: value })
    })
      .then((resp) => resp.json())
      .then((data) => {
        if (data.success) {
          const display = document.getElementById(`field-display-${controlId}-${fieldName}`)
          display.innerHTML = value
            ? '<div style="white-space: pre-wrap;">' + this.#escapeHtml(value) + "</div>"
            : '<span class="text-body-tertiary fst-italic" style="font-size: 0.82rem;">Click &#x270E; to add</span>'
          this.#toggleField(controlId, fieldName)
        } else {
          alert("Error: " + (data.error || "Unknown error"))
        }
      })
      .catch((err) => { alert("Save failed: " + err.message) })
  }

  // ── Control-level resource linking ────────────────────────────────────
  toggleAddRef(event) {
    const id = event.params.id
    const form = document.getElementById(`add-ref-${id}`)
    const btn = document.getElementById(`add-ref-btn-${id}`)
    if (!form || !btn) return
    const visible = form.style.display !== "none"
    form.style.display = visible ? "none" : ""
    btn.style.display = visible ? "" : "none"
    if (!visible) {
      const title = document.getElementById(`ref-title-${id}`)
      if (title) title.focus()
    }
  }

  create(event) {
    const controlId = event.params.controlId
    const title = document.getElementById(`ref-title-${controlId}`).value.trim()
    if (!title) { alert("Title is required"); return }
    const href = document.getElementById(`ref-href-${controlId}`).value.trim()
    const mediaType = document.getElementById(`ref-media-${controlId}`).value.trim()

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

  #toggleField(controlId, fieldName) {
    this.toggleFieldEdit({ params: { controlId, fieldName } })
  }

  #escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  #headers() {
    return {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
      "Accept": "application/json"
    }
  }
}
