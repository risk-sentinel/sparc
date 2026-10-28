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
//   icon — the toggle button; it holds both icons and CSS shows the right one
//
// Actions:
//   theme#toggle — flip between light and dark
export default class ThemeController extends Controller {
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
    const current = document.documentElement.dataset.bsTheme
    const next = current === "dark" ? "light" : "dark"
    localStorage.setItem("sparc-theme", next)
    document.documentElement.dataset.bsTheme = next
    this.updateIcon()
  }

  // ── Private ──

  applyTheme() {
    const saved = localStorage.getItem("sparc-theme")
    if (saved) {
      document.documentElement.dataset.bsTheme = saved
    } else {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      document.documentElement.dataset.bsTheme = systemDark ? "dark" : "light"
    }
  }

  handleSystemChange() {
    // Auto-switch only if the user hasn't manually toggled
    if (!localStorage.getItem("sparc-theme")) {
      const systemDark = window.matchMedia("(prefers-color-scheme: dark)").matches
      document.documentElement.dataset.bsTheme = systemDark ? "dark" : "light"
      this.updateIcon()
    }
  }

  // #1289 — the button holds a sun and a moon icon and CSS shows the one for
  // the current theme; only the tooltip is set here.
  updateIcon() {
    if (!this.hasIconTarget) return

    const dark = document.documentElement.dataset.bsTheme === "dark"
    this.iconTarget.title = dark ? "Switch to light mode" : "Switch to dark mode"
  }
}
