import { Controller } from "@hotwired/stimulus"

// #1390 part G — a reviewer's questions to the provider about a received
// version. "Ask about this" on any section, entry, field, change or error adds
// that place (its JSON Pointer, location, what is there and the compared
// values) to the list; each question can carry the reviewer's own words. The
// list goes with Respond or Reject as questions[] and is exported with the
// review to send to the provider out of band.
//
// Kept in sessionStorage per version while the reviewer moves between tabs
// (a convenience only; nothing is saved until Respond or Reject). Built with
// DOM text nodes, never innerHTML: provider text stays inert (SI-10).
const FIELDS = ["pointer", "label", "detail", "before", "after", "question"]

export default class extends Controller {
  static targets = ["ask", "tray", "count", "empty", "fields", "note", "clear"]
  static values = { key: String }

  connect() {
    this.questions = this.load()
    this.sync()
  }

  toggle(event) {
    const question = this.fromButton(event.currentTarget)
    const index = this.questions.findIndex(q => q.pointer === question.pointer)
    if (index >= 0) this.questions.splice(index, 1)
    else this.questions.push(question)
    this.save()
    this.sync()
  }

  // "Ask the provider to fix these": every ask control inside the group the
  // button names (the group is marked data-ask-group, so the button itself,
  // which carries data-group, is never mistaken for it).
  addGroup(event) {
    const group = this.element.querySelector(`[data-ask-group="${event.currentTarget.dataset.group}"]`)
    if (!group) return
    group.querySelectorAll("[data-review-questions-target='ask']").forEach(button => {
      const question = this.fromButton(button)
      if (!this.questions.some(q => q.pointer === question.pointer)) this.questions.push(question)
    })
    this.save()
    this.sync()
  }

  remove(event) {
    this.questions.splice(Number(event.currentTarget.dataset.index), 1)
    this.save()
    this.sync()
  }

  clear() {
    this.questions = []
    this.save()
    this.sync()
  }

  edit(event) {
    const question = this.questions[Number(event.currentTarget.dataset.index)]
    if (!question) return
    question.question = event.currentTarget.value
    this.save()
    this.writeFields()
  }

  // The questions travel with the form; the draft in this browser is done.
  submitted() {
    try { window.sessionStorage.removeItem(this.storageKey) } catch (_e) { /* nothing stored */ }
  }

  // After a tab or comparison loads in the viewer frame, mark what is asked.
  sync() {
    const asked = new Set(this.questions.map(q => q.pointer))
    this.askTargets.forEach(button => {
      const on = asked.has(button.dataset.pointer)
      button.setAttribute("aria-pressed", on ? "true" : "false")
      button.textContent = on ? "Asked" : "Ask about this"
    })
    this.renderTray()
    this.writeFields()
  }

  fromButton(button) {
    const q = {}
    FIELDS.forEach(f => { if (button.dataset[f]) q[f] = button.dataset[f] })
    return q
  }

  renderTray() {
    if (this.hasCountTarget) this.countTarget.textContent = String(this.questions.length)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = this.questions.length > 0
    if (this.hasClearTarget) this.clearTarget.hidden = this.questions.length === 0
    if (!this.hasTrayTarget) return

    const tray = this.trayTarget
    tray.replaceChildren()
    this.questions.forEach((q, i) => {
      const item = document.createElement("li")
      item.className = "sparc-viewer-tray__item"
      const label = document.createElement("strong")
      label.textContent = q.label || q.pointer || "General"
      item.appendChild(label)
      if (q.detail) {
        const detail = document.createElement("div")
        detail.className = "small text-body-secondary"
        detail.textContent = q.detail
        item.appendChild(detail)
      }
      const input = document.createElement("input")
      input.type = "text"
      input.className = "form-control form-control-sm mt-1"
      input.id = `review-question-${i}`
      input.placeholder = "Your question (optional)"
      input.setAttribute("aria-label", `Your question about ${q.label || q.pointer}`)
      input.value = q.question || ""
      input.dataset.index = String(i)
      input.dataset.action = "input->review-questions#edit"
      item.appendChild(input)
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "sparc-viewer-ask mt-1"
      remove.textContent = "Remove"
      remove.dataset.index = String(i)
      remove.dataset.action = "review-questions#remove"
      remove.setAttribute("aria-label", `Remove the question about ${q.label || q.pointer}`)
      item.appendChild(remove)
      tray.appendChild(item)
    })
  }

  // questions[][field] hidden inputs in the Respond and Reject forms; a note
  // is optional once there is at least one question.
  writeFields() {
    this.fieldsTargets.forEach(container => {
      container.replaceChildren()
      this.questions.forEach(q => {
        FIELDS.forEach(f => {
          if (!q[f]) return
          const input = document.createElement("input")
          input.type = "hidden"
          input.name = `questions[][${f}]`
          input.value = q[f]
          container.appendChild(input)
        })
      })
    })
    this.noteTargets.forEach(note => { note.required = this.questions.length === 0 })
  }

  load() {
    try {
      const raw = window.sessionStorage.getItem(this.storageKey)
      const list = raw ? JSON.parse(raw) : []
      return Array.isArray(list) ? list.filter(q => q && typeof q.pointer === "string") : []
    } catch (_e) {
      return []
    }
  }

  save() {
    try { window.sessionStorage.setItem(this.storageKey, JSON.stringify(this.questions)) } catch (_e) { /* storage blocked: the list still works on this page */ }
  }

  get storageKey() { return `sparc:${this.keyValue}:questions` }
}
