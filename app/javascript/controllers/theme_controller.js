import { Controller } from "@hotwired/stimulus"

// Stimulus controller for light/dark theme switching.
//
// Respects OS-level prefers-color-scheme on first visit, allows manual
// override (persisted in localStorage), and provides a "use system"
// reset that clears the override and re-follows the OS preference.
//
// Place data-controller="theme" on the <body> element (or any wrapper).
//
// Targets:
//   icon — the toggle button element whose text content shows the current mode
//
// Actions:
//   theme#toggle — cycle: light → dark → system (clears override)
//   theme#setLight / theme#setDark / theme#useSystem — explicit setters
export default class extends Controller {
  static targets = ["icon"]

  connect() {
    this.applyTheme()
    this.updateIcon()

    this.boundSystemChange = this.handleSystemChange.bind(this)
    this.mediaQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.mediaQuery.addEventListener("change", this.boundSystemChange)
  }

  disconnect() {
    if (this.mediaQuery) {
      this.mediaQuery.removeEventListener("change", this.boundSystemChange)
    }
  }

  // Action: cycle through light → dark → system
  toggle() {
    const saved = localStorage.getItem("sparc-theme")
    const current = document.documentElement.getAttribute("data-bs-theme")

    if (saved === "light" || (!saved && current === "light")) {
      // Currently light (whether saved or system) → switch to dark
      this.setExplicit("dark")
    } else if (saved === "dark" || (!saved && current === "dark")) {
      // Currently dark → switch to system
      this.useSystem()
    } else {
      // Fallback: go to light
      this.setExplicit("light")
    }
  }

  setLight() {
    this.setExplicit("light")
  }

  setDark() {
    this.setExplicit("dark")
  }

  useSystem() {
    localStorage.removeItem("sparc-theme")
    const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    document.documentElement.setAttribute("data-bs-theme", systemDark ? "dark" : "light")
    this.updateIcon()
  }

  // ── Private ──

  applyTheme() {
    const saved = localStorage.getItem("sparc-theme")
    if (saved) {
      document.documentElement.setAttribute("data-bs-theme", saved)
    } else {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      document.documentElement.setAttribute("data-bs-theme", systemDark ? "dark" : "light")
    }
  }

  handleSystemChange() {
    // Only auto-switch if the user hasn't set an explicit override
    if (!localStorage.getItem("sparc-theme")) {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      document.documentElement.setAttribute("data-bs-theme", systemDark ? "dark" : "light")
      this.updateIcon()
    }
  }

  setExplicit(theme) {
    localStorage.setItem("sparc-theme", theme)
    document.documentElement.setAttribute("data-bs-theme", theme)
    this.updateIcon()
  }

  updateIcon() {
    if (!this.hasIconTarget) return

    const saved = localStorage.getItem("sparc-theme")
    const current = document.documentElement.getAttribute("data-bs-theme")

    if (!saved) {
      // Following system — show computer icon
      this.iconTarget.textContent = "\uD83D\uDCBB"
      this.iconTarget.title = "Theme: System \u2014 click to switch"
    } else if (current === "dark") {
      // Explicit dark — show sun (click to go to system)
      this.iconTarget.textContent = "\u2600\uFE0F"
      this.iconTarget.title = "Theme: Dark \u2014 click to use system"
    } else {
      // Explicit light — show moon (click to go to dark)
      this.iconTarget.textContent = "\uD83C\uDF19"
      this.iconTarget.title = "Theme: Light \u2014 click to switch to dark"
    }
  }
}
