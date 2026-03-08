// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// ── Bootstrap component re-initialization after Turbo Drive navigation ──
//
// Bootstrap 5 auto-initializes components (dropdowns, collapses, etc.) on
// DOMContentLoaded.  Turbo Drive replaces the <body> without firing that
// event, so Bootstrap event listeners are lost after navigation.
//
// turbo:load fires on every Turbo visit AND on the initial page load,
// so this single handler covers both cases reliably.
document.addEventListener("turbo:load", () => {
  // Re-initialize all dropdown toggles
  document.querySelectorAll('[data-bs-toggle="dropdown"]').forEach((el) => {
    if (window.bootstrap) {
      bootstrap.Dropdown.getOrCreateInstance(el)
    }
  })

  // Re-initialize all collapse toggles (navbar toggler, accordions, etc.)
  document.querySelectorAll('[data-bs-toggle="collapse"]').forEach((el) => {
    if (window.bootstrap) {
      bootstrap.Collapse.getOrCreateInstance(el, { toggle: false })
    }
  })
})
