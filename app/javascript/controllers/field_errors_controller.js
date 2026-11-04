import { Controller } from "@hotwired/stimulus"

// #1340 — a form that is redrawn in place after a save keeps the author's
// place, and a section holding a field with an error stays open.
//
// - Before a submit it notes which <details> sections are open; when the form
//   comes back (a Turbo frame render) it reopens them, so a save never
//   collapses what the author had open.
// - Every section holding an invalid field is opened, and can't be collapsed
//   while the field is invalid.
// - Editing an invalid field clears its mark (the server checks again on the
//   next save), and its section may collapse again.
// - After a failed save the first invalid field takes focus.
//
// Used on: the SSP Enrich form. Every other form adopts it in the next update.
const openSections = new Map()

export default class FieldErrorsController extends Controller {
  static values = { key: String }

  connect() {
    const remembered = openSections.get(this.keyValue)
    if (remembered) {
      for (const id of remembered) document.getElementById(id)?.setAttribute("open", "")
      openSections.delete(this.keyValue)
    }
    this.#invalidFields().forEach((field) => this.#sectionOf(field)?.setAttribute("open", ""))
    this.element.addEventListener("submit", this.#remember)
    this.element.addEventListener("click", this.#holdOpen, true)
    this.element.addEventListener("input", this.#clear)
    this.element.addEventListener("change", this.#clear)
    const first = this.#invalidFields()[0]
    if (first) first.focus({ preventScroll: false })
  }

  disconnect() {
    this.element.removeEventListener("submit", this.#remember)
    this.element.removeEventListener("click", this.#holdOpen, true)
    this.element.removeEventListener("input", this.#clear)
    this.element.removeEventListener("change", this.#clear)
  }

  #remember = () => {
    const ids = [...this.element.querySelectorAll("details[open][id]")].map((d) => d.id)
    openSections.set(this.keyValue, ids)
  }

  // A click on the summary of an open section that holds an invalid field
  // would collapse it: refuse, and say why.
  #holdOpen = (event) => {
    const summary = event.target.closest("summary")
    const section = summary?.parentElement
    if (section?.tagName !== "DETAILS" || !section.open) return
    if (section.querySelector(".is-invalid")) {
      event.preventDefault()
      summary.setAttribute("title", "Fix the highlighted fields before collapsing this section")
    }
  }

  #clear = (event) => {
    const field = event.target
    if (!field.classList?.contains("is-invalid")) return
    field.classList.remove("is-invalid")
    field.removeAttribute("aria-invalid")
    const feedbackId = (field.getAttribute("aria-describedby") || "").split(" ").find((id) => id.endsWith("-error"))
    if (feedbackId) document.getElementById(feedbackId)?.remove()
    const section = this.#sectionOf(field)
    if (section && !section.querySelector(".is-invalid")) section.querySelector("summary")?.removeAttribute("title")
  }

  #invalidFields() { return [...this.element.querySelectorAll(".is-invalid")] }

  #sectionOf(field) { return field.closest("details") }
}
