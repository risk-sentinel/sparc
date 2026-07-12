import { Controller } from "@hotwired/stimulus"

// Persists sidebar collapse section state (expanded/collapsed) across page navigations.
export default class SidebarController extends Controller {
  static SECTIONS_KEY = "sparc_sidebar_sections"

  connect() {
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
    } catch {
      localStorage.removeItem(this.constructor.SECTIONS_KEY)
    }
  }

  saveSectionState(id, expanded) {
    const saved = localStorage.getItem(this.constructor.SECTIONS_KEY)
    let sections = {}
    try { sections = saved ? JSON.parse(saved) : {} } catch { /* ignore */ }
    sections[id] = expanded
    localStorage.setItem(this.constructor.SECTIONS_KEY, JSON.stringify(sections))
  }
}
