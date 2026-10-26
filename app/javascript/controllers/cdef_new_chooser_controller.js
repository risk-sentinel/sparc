import { Controller } from "@hotwired/stimulus"

// The new-CDEF screen offers three independent ways in — upload, author,
// generate from a profile — each with its own form. This shows one at a time,
// as tabs, so the forms cannot be mistaken for one long form.
//
// - A choice can be linked directly: /cdef_documents/new#author.
// - The server can open a choice (a rejected authored CDEF re-renders on
//   Author) through data-cdef-new-chooser-default-value; a link's hash wins.
// - Without JavaScript the chooser stays hidden and every form shows.
export default class CdefNewChooserController extends Controller {
  static targets = ["chooser", "tab", "panel"]
  static values = { default: { type: String, default: "upload" } }

  connect() {
    this.chooserTarget.hidden = false
    this.onHashChange = () => this.#show(this.#fromHash(), { focus: false })
    window.addEventListener("hashchange", this.onHashChange)
    this.#show(this.#fromHash() || this.defaultValue, { focus: false, updateHash: false })
  }

  disconnect() {
    window.removeEventListener("hashchange", this.onHashChange)
  }

  select(event) {
    this.#show(event.currentTarget.dataset.choice, { focus: false })
  }

  // Arrow keys, Home and End move between the choices (WAI-ARIA tabs pattern).
  navigate(event) {
    const keys = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }
    const tabs = this.tabTargets
    const at = tabs.indexOf(event.currentTarget)
    let next
    if (event.key in keys) next = (at + keys[event.key] + tabs.length) % tabs.length
    else if (event.key === "Home") next = 0
    else if (event.key === "End") next = tabs.length - 1
    else return
    event.preventDefault()
    this.#show(tabs[next].dataset.choice, { focus: true })
  }

  #fromHash() {
    const key = window.location.hash.replace(/^#/, "")
    return this.#choices().includes(key) ? key : null
  }

  #choices() {
    return this.tabTargets.map((t) => t.dataset.choice)
  }

  #show(key, { focus, updateHash = true }) {
    if (!this.#choices().includes(key)) return
    this.tabTargets.forEach((tab) => {
      const on = tab.dataset.choice === key
      tab.setAttribute("aria-selected", String(on))
      tab.tabIndex = on ? 0 : -1
      if (on && focus) tab.focus()
    })
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.choice !== key
    })
    if (updateHash && window.location.hash !== `#${key}`) {
      history.replaceState(history.state, "", `#${key}`)
    }
  }
}
