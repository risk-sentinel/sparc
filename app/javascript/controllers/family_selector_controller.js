import { Controller } from "@hotwired/stimulus"

// Stimulus controller for family-level control selection in profile creation
// and management pages.
//
// Supports two modes:
//   1. Dynamic mode (select_catalog) — builds family accordion HTML from
//      catalog JSON after user selects a catalog.
//   2. Server-rendered mode (manage_controls) — detects existing checkboxes
//      on connect() and syncs family checkbox state.
//
// Place data-controller="family-selector" on a wrapping element.
//
// Values:
//   catalog-url  — base URL for catalog JSON (e.g., "/control_catalogs")
//   mode         — "dynamic" (default) or "server-rendered"
export default class extends Controller {
  static targets = [
    "catalogSelect",
    "baselineSelect",
    "controlsList",
    "selectedCount",
    "controlsSection"
  ]

  static values = {
    catalogUrl: { type: String, default: "/control_catalogs" },
    mode: { type: String, default: "dynamic" }
  }

  connect() {
    if (this.modeValue === "server-rendered") {
      this.syncAllFamilies()
      this.updateCount()
    }
  }

  // ── Actions ──────────────────────────────────────────────────────

  // Fired when the catalog <select> changes (dynamic mode only).
  catalogChanged() {
    const catalogId = this.catalogSelectTarget.value
    if (!catalogId) {
      this.controlsSectionTarget.style.display = "none"
      return
    }

    this.controlsSectionTarget.style.display = "block"
    this.controlsListTarget.innerHTML = '<p class="text-muted">Loading controls...</p>'

    fetch(`${this.catalogUrlValue}/${catalogId}.json`)
      .then(response => response.json())
      .then(data => this.buildFamilyHtml(data.control_families || []))
      .catch(() => {
        this.controlsListTarget.innerHTML = '<p class="text-danger">Failed to load controls. Try again.</p>'
      })
  }

  // Fired when the baseline <select> changes.
  // Fetches baseline-eligible control IDs from the server, then checks them.
  baselineChanged() {
    const level = this.baselineSelectTarget.value
    if (!level) return

    const catalogId = this.modeValue === "dynamic"
      ? this.catalogSelectTarget.value
      : this.element.dataset.familySelectorCatalogId

    if (!catalogId) return

    fetch(`${this.catalogUrlValue}/${catalogId}/baseline_controls?level=${encodeURIComponent(level)}`)
      .then(response => response.json())
      .then(data => {
        const ids = new Set(data.control_ids || [])
        this.controlCheckboxes().forEach(cb => {
          cb.checked = ids.has(cb.value)
        })
        this.syncAllFamilies()
        this.updateCount()
      })
      .catch(() => {
        // Silently fail — baseline auto-select is convenience, not critical
      })
  }

  // Fired when a family-level checkbox is toggled.
  toggleFamily(event) {
    const checkbox = event.currentTarget
    const familyCode = checkbox.dataset.family
    const checked = checkbox.checked

    this.controlCheckboxesForFamily(familyCode).forEach(cb => {
      cb.checked = checked
    })
    this.updateFamilyIndicator(familyCode)
    this.updateCount()
  }

  // Fired when an individual control checkbox changes.
  controlChanged(event) {
    const familyCode = event.currentTarget.dataset.family
    this.syncFamily(familyCode)
    this.updateCount()
  }

  // Select all controls across all families.
  selectAll() {
    this.controlCheckboxes().forEach(cb => { cb.checked = true })
    this.syncAllFamilies()
    this.updateCount()
  }

  // Deselect all controls across all families.
  deselectAll() {
    this.controlCheckboxes().forEach(cb => { cb.checked = false })
    this.syncAllFamilies()
    this.updateCount()
  }

  // Expand all family <details> elements.
  expandAll() {
    this.familyDetails().forEach(d => { d.open = true })
  }

  // Collapse all family <details> elements.
  collapseAll() {
    this.familyDetails().forEach(d => { d.open = false })
  }

  // ── Private ──────────────────────────────────────────────────────

  // Build family accordion HTML from catalog JSON data (dynamic mode).
  buildFamilyHtml(families) {
    if (!families.length) {
      this.controlsListTarget.innerHTML = '<p class="text-muted">No controls found in this catalog.</p>'
      return
    }

    let html = ""
    families.forEach(family => {
      const controls = family.catalog_controls || []
      const count = controls.length

      html += `<details class="sparc-family-group">`
      html += `<summary>`
      html += `<input type="checkbox" class="form-check-input family-checkbox" data-family="${this.escapeHtml(family.code)}" data-action="change->family-selector#toggleFamily">`
      html += ` <strong>${this.escapeHtml(family.code)}</strong> - ${this.escapeHtml(family.name)}`
      html += ` <span class="badge bg-secondary">${count}</span>`
      html += ` <span class="sparc-family-indicator" data-family-indicator="${this.escapeHtml(family.code)}">0 / ${count} selected</span>`
      html += `</summary>`
      html += `<div class="ms-4 mt-2">`

      controls.forEach(ctrl => {
        const id = `ctrl-${this.escapeHtml(ctrl.control_id)}`
        html += `<div class="form-check">`
        html += `<input class="form-check-input control-checkbox" type="checkbox" name="control_ids[]" value="${this.escapeHtml(ctrl.control_id)}" id="${id}" data-family="${this.escapeHtml(family.code)}" data-action="change->family-selector#controlChanged">`
        html += `<label class="form-check-label" for="${id}">`
        html += `<strong>${this.escapeHtml(ctrl.control_id)}</strong>`
        if (ctrl.title) html += ` - ${this.escapeHtml(ctrl.title)}`
        html += `</label></div>`
      })

      html += `</div></details>`
    })

    this.controlsListTarget.innerHTML = html
    this.updateCount()
  }

  // Sync a single family checkbox state based on its child checkboxes.
  syncFamily(familyCode) {
    const checkboxes = this.controlCheckboxesForFamily(familyCode)
    const familyCheckbox = this.familyCheckbox(familyCode)
    if (!familyCheckbox || !checkboxes.length) return

    const checkedCount = checkboxes.filter(cb => cb.checked).length

    if (checkedCount === 0) {
      familyCheckbox.checked = false
      familyCheckbox.indeterminate = false
    } else if (checkedCount === checkboxes.length) {
      familyCheckbox.checked = true
      familyCheckbox.indeterminate = false
    } else {
      familyCheckbox.checked = false
      familyCheckbox.indeterminate = true
    }

    this.updateFamilyIndicator(familyCode)
  }

  // Sync all family checkboxes.
  syncAllFamilies() {
    const families = new Set()
    this.controlCheckboxes().forEach(cb => {
      if (cb.dataset.family) families.add(cb.dataset.family)
    })
    families.forEach(code => this.syncFamily(code))
  }

  // Update the "X / Y selected" indicator for a family.
  updateFamilyIndicator(familyCode) {
    const indicator = this.controlsListTarget.querySelector(`[data-family-indicator="${familyCode}"]`)
    if (!indicator) return

    const checkboxes = this.controlCheckboxesForFamily(familyCode)
    const checkedCount = checkboxes.filter(cb => cb.checked).length
    indicator.textContent = `${checkedCount} / ${checkboxes.length} selected`
  }

  // Update the global selected count.
  updateCount() {
    const count = this.controlCheckboxes().filter(cb => cb.checked).length
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = count
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────

  controlCheckboxes() {
    return Array.from(this.controlsListTarget.querySelectorAll(".control-checkbox"))
  }

  controlCheckboxesForFamily(familyCode) {
    return Array.from(
      this.controlsListTarget.querySelectorAll(`.control-checkbox[data-family="${familyCode}"]`)
    )
  }

  familyCheckbox(familyCode) {
    return this.controlsListTarget.querySelector(`.family-checkbox[data-family="${familyCode}"]`)
  }

  familyDetails() {
    return Array.from(this.controlsListTarget.querySelectorAll("details.sparc-family-group"))
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
