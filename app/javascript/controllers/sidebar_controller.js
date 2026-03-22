import { Controller } from "@hotwired/stimulus"

// Manages sidebar offcanvas state persistence across page navigations.
// Stores open/closed state and expanded sections in localStorage.
export default class extends Controller {
  static STORAGE_KEY = "sparc_sidebar_open"
  static SECTIONS_KEY = "sparc_sidebar_sections"

  connect() {
    // Restore sidebar open state
    if (localStorage.getItem(this.constructor.STORAGE_KEY) === "true") {
      const offcanvas = bootstrap.Offcanvas.getOrCreateInstance(this.element)
      offcanvas.show()
    }

    // Track show/hide events for persistence
    this.element.addEventListener("shown.bs.offcanvas", () => {
      localStorage.setItem(this.constructor.STORAGE_KEY, "true")
    })
    this.element.addEventListener("hidden.bs.offcanvas", () => {
      localStorage.setItem(this.constructor.STORAGE_KEY, "false")
    })

    // Restore expanded collapse sections
    this.restoreSections()

    // Track collapse section changes
    this.element.addEventListener("shown.bs.collapse", (e) => this.saveSectionState(e.target.id, true))
    this.element.addEventListener("hidden.bs.collapse", (e) => this.saveSectionState(e.target.id, false))
  }

  restoreSections() {
    const saved = localStorage.getItem(this.constructor.SECTIONS_KEY)
    if (!saved) return

    try {
      const sections = JSON.parse(saved)
      Object.entries(sections).forEach(([id, expanded]) => {
        const el = document.getElementById(id)
        if (!el) return
        if (expanded && !el.classList.contains("show")) {
          el.classList.add("show")
        } else if (!expanded && el.classList.contains("show")) {
          el.classList.remove("show")
        }
      })
    } catch (e) {
      // Invalid JSON — clear and start fresh
      localStorage.removeItem(this.constructor.SECTIONS_KEY)
    }
  }

  saveSectionState(id, expanded) {
    const saved = localStorage.getItem(this.constructor.SECTIONS_KEY)
    let sections = {}
    try { sections = saved ? JSON.parse(saved) : {} } catch (e) { /* ignore */ }
    sections[id] = expanded
    localStorage.setItem(this.constructor.SECTIONS_KEY, JSON.stringify(sections))
  }
}
