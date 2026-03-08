import { Controller } from "@hotwired/stimulus"

// Stimulus controller for light/dark theme switching.
//
// Defaults to OS prefers-color-scheme on first visit. Each click
// toggles between light and dark (two-state). The choice is saved
// in localStorage so it persists across page loads.
//
// If the OS preference changes and the user hasn't manually toggled,
// the UI follows the OS automatically.
//
// Targets:
//   icon — the toggle button element whose text content shows the current mode
//
// Actions:
//   theme#toggle — flip between light and dark
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

  // Action: simple two-state toggle — light ↔ dark
  toggle() {
    const current = document.documentElement.getAttribute("data-bs-theme")
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem("sparc-theme", next)
    document.documentElement.setAttribute("data-bs-theme", next)
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
    // Auto-switch only if the user hasn't manually toggled
    if (!localStorage.getItem("sparc-theme")) {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      document.documentElement.setAttribute("data-bs-theme", systemDark ? "dark" : "light")
      this.updateIcon()
    }
  }

  updateIcon() {
    if (!this.hasIconTarget) return

    const current = document.documentElement.getAttribute("data-bs-theme")
    if (current === "dark") {
      // Dark mode active — show sun icon (click to switch to light)
      this.iconTarget.textContent = "\u2600\uFE0F"
      this.iconTarget.title = "Switch to light mode"
    } else {
      // Light mode active — show moon icon (click to switch to dark)
      this.iconTarget.textContent = "\uD83C\uDF19"
      this.iconTarget.title = "Switch to dark mode"
    }
  }
}
