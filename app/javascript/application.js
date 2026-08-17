// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// ── Custom Turbo confirmation modal (Bootstrap 5) ──
// Replaces browser-native window.confirm() with a styled Bootstrap modal
// for all turbo_confirm dialogs app-wide.
Turbo.config.forms.confirm = (message, element) => {
  return new Promise((resolve) => {
    const modalId = "sparc-confirm-modal"
    let existing = document.getElementById(modalId)
    if (existing) existing.remove()

    // Detect destructive actions: DELETE method or explicit data attribute
    const form = element?.closest("form") || element
    const method = (form?.querySelector("input[name='_method']")?.value || form?.method || "").toUpperCase()
    const isDestructive = method === "DELETE" || element?.dataset?.turboConfirmDestructive === "true"
    const buttonLabel = isDestructive ? "Delete" : "Confirm"
    const buttonClass = isDestructive ? "btn btn-danger" : "btn btn-primary"

    const wrapper = document.createElement("div")
    wrapper.innerHTML = [
      '<div class="modal fade" id="' + modalId + '" tabindex="-1" aria-hidden="true">',
      '  <div class="modal-dialog modal-dialog-centered">',
      '    <div class="modal-content">',
      '      <div class="modal-header">',
      '        <h5 class="modal-title">Confirm Action</h5>',
      '        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>',
      '      </div>',
      '      <div class="modal-body"></div>',
      '      <div class="modal-footer">',
      '        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>',
      '        <button type="button" class="' + buttonClass + '" id="' + modalId + '-confirm">' + buttonLabel + '</button>',
      '      </div>',
      '    </div>',
      '  </div>',
      '</div>'
    ].join("\n")

    const modal = wrapper.firstElementChild
    modal.querySelector(".modal-body").textContent = message
    document.body.appendChild(modal)

    const bsModal = new bootstrap.Modal(modal)
    let resolved = false

    modal.querySelector("#" + modalId + "-confirm").addEventListener("click", () => {
      resolved = true
      resolve(true)
      bsModal.hide()
    })

    modal.addEventListener("hidden.bs.modal", () => {
      if (!resolved) resolve(false)
      modal.remove()
    }, { once: true })

    bsModal.show()
  })
}

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
// #942 — mirrors app/lib/parameter_value_list.rb. A multi-valued parameter used
// to be comma-joined, but OSCAL insert markup always contains a comma, so a
// composed choice ("establish {{ insert: param, ac-20_odp.02 }}") split in half.
// Of 355 selection choices in the Rev 5 catalog, 74 contain a comma and none
// contains a pipe. Keep the two implementations in step.
const PARAM_VALUE_SEPARATOR = " | "
const PARAM_INSERT_PATTERN = /\{\{\s*insert:\s*param,\s*[^}\s]+\s*\}\}/

function splitParamValues(value) {
  const text = (value ?? "").trim()
  if (!text) return []
  if (text.includes(PARAM_VALUE_SEPARATOR)) {
    return text.split(PARAM_VALUE_SEPARATOR).map(v => v.trim()).filter(v => v.length > 0)
  }
  // Never split a value that references a parameter — splitting is what
  // corrupts it, and such a value is never a comma-separated list.
  if (PARAM_INSERT_PATTERN.test(text)) return [text]
  return text.split(",").map(v => v.trim()).filter(v => v.length > 0)
}

window.sparc.pickParamChoice = function(badge) {
  const input = badge.closest("td").querySelector("input[type='text']")
  if (!input) return

  // #942 — the badge SHOWS the resolved wording ("establish terms and
  // conditions") but the value written back must be the verbatim OSCAL
  // ("establish {{ insert: param, ac-20_odp.02 }}"), or the document stops
  // round-tripping. Falls back to the text for badges with no reference.
  const choiceValue = badge => badge.dataset.choiceValue ?? badge.textContent.trim()

  const choice = choiceValue(badge)
  const isMulti = badge.dataset.multi === "true"

  if (isMulti) {
    const values = splitParamValues(input.value)
    const idx = values.indexOf(choice)
    if (idx >= 0) {
      values.splice(idx, 1)
    } else {
      values.push(choice)
    }
    input.value = values.join(PARAM_VALUE_SEPARATOR)
  } else {
    input.value = input.value.trim() === choice ? "" : choice
  }

  // Highlight active badges
  badge.closest("td").querySelectorAll(".sparc-param-choice").forEach(b => {
    const val = choiceValue(b)
    const current = splitParamValues(input.value)
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

  // #870 — field-level help tooltips (see ApplicationHelper#field_help).
  // Same turbo:load pattern as the widgets above: Turbo Drive swaps the body
  // without a full page load, so anything Bootstrap instantiated on the old
  // DOM is gone and has to be re-created here.
  //
  // Default trigger is "hover focus", which is deliberate — help that only
  // appears on hover cannot be reached by keyboard or touch.
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    if (window.bootstrap) {
      bootstrap.Tooltip.getOrCreateInstance(el)
    }
  })
})

// Tooltips attach their popup to <body>, outside the element Turbo replaces.
// Without this, navigating away while one is visible leaves it stranded on the
// next screen with nothing to dismiss it.
document.addEventListener("turbo:before-render", () => {
  if (!window.bootstrap) return
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach((el) => {
    bootstrap.Tooltip.getInstance(el)?.dispose()
  })
})
