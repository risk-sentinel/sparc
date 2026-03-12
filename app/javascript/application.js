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
// ── SPARC global helpers (namespaced under window.sparc) ──
window.sparc = window.sparc || {}

// Parameter suggestion badge click handler.
// Single-select: replaces the text input value.
// Multi-select (one-or-more): appends with ", " separator (toggle off if already present).
window.sparc.pickParamChoice = function(badge) {
  const input = badge.closest("td").querySelector("input[type='text']")
  if (!input) return

  const choice = badge.textContent.trim()
  const isMulti = badge.dataset.multi === "true"

  if (isMulti) {
    const values = input.value.split(",").map(v => v.trim()).filter(v => v.length > 0)
    const idx = values.indexOf(choice)
    if (idx >= 0) {
      values.splice(idx, 1)
    } else {
      values.push(choice)
    }
    input.value = values.join(", ")
  } else {
    input.value = input.value.trim() === choice ? "" : choice
  }

  // Highlight active badges
  badge.closest("td").querySelectorAll(".sparc-param-choice").forEach(b => {
    const val = b.textContent.trim()
    const current = input.value.split(",").map(v => v.trim())
    if (current.includes(val)) {
      b.classList.remove("bg-primary-subtle", "text-primary-emphasis")
      b.classList.add("bg-primary", "text-white")
    } else {
      b.classList.remove("bg-primary", "text-white")
      b.classList.add("bg-primary-subtle", "text-primary-emphasis")
    }
  })
}

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
