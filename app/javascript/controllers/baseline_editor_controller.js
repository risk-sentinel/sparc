import { Controller } from "@hotwired/stimulus"

// Stimulus controller for inline and bulk baseline-impact editing on the
// control family show page.
//
// Place data-controller="baseline-editor" on the wrapping element.
//
// Values:
//   update-url  — URL for single-control PATCH (update_baseline)
//   bulk-url    — URL for multi-control PATCH (bulk_update_baselines)
export default class BaselineEditorController extends Controller {
  static targets = [
    "checkbox",
    "selectAll",
    "bulkToolbar",
    "bulkCount",
    "bulkLevel",
    "bulkAction",
    "editToggle"
  ]

  static values = {
    updateUrl: String,
    bulkUrl: String
  }

  connect() {
    this.editing = false
  }

  // ── Toggle edit mode ───────────────────────────────────────────

  toggleEdit() {
    this.editing = !this.editing
    const editElements = this.element.querySelectorAll("[data-baseline-edit]")
    const viewElements = this.element.querySelectorAll("[data-baseline-view]")
    const checkboxCells = this.element.querySelectorAll("[data-baseline-checkbox-cell]")

    editElements.forEach(el => { el.style.display = this.editing ? "" : "none" })
    viewElements.forEach(el => { el.style.display = this.editing ? "none" : "" })
    checkboxCells.forEach(el => { el.style.display = this.editing ? "" : "none" })

    if (this.hasBulkToolbarTarget) {
      this.bulkToolbarTarget.style.display = this.editing ? "" : "none"
    }

    if (this.hasEditToggleTarget) {
      this.editToggleTarget.textContent = this.editing ? "Done Editing" : "Manage Baselines"
    }

    // Uncheck all when exiting edit mode
    if (!this.editing) {
      this.checkboxTargets.forEach(cb => { cb.checked = false })
      if (this.hasSelectAllTarget) this.selectAllTarget.checked = false
      this.updateBulkCount()
    }
  }

  // ── Inline edit ────────────────────────────────────────────────

  // Fired when an inline baseline checkbox is toggled for a single control.
  inlineToggle(event) {
    const row = event.target.closest("[data-control-db-id]")
    if (!row) return

    const controlId = row.dataset.controlDbId
    const checkboxes = row.querySelectorAll("input[data-baseline-level]")
    const levels = []
    checkboxes.forEach(cb => {
      if (cb.checked) levels.push(cb.dataset.baselineLevel)
    })

    const impact = levels.join(", ") || ""
    this.patchBaseline(controlId, impact, row)
  }

  patchBaseline(controlId, impact, row) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({ control_id: controlId, baseline_impact: impact })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.updateBadges(row, data.baseline_impact)
      } else {
        alert(data.error || "Failed to update baseline")
      }
    })
    .catch(() => alert("Network error — could not update baseline"))
  }

  updateBadges(row, baselineImpact) {
    const badgeContainer = row.querySelector("[data-baseline-badges]")
    if (!badgeContainer) return

    const levels = (baselineImpact || "").split(",").map(s => s.trim()).filter(Boolean)
    const colorMap = { "LOW": "badge-ok", "MODERATE": "badge-info", "HIGH": "badge-warn" }

    if (levels.length === 0) {
      badgeContainer.innerHTML = '<span style="color: #ddd;">&mdash;</span>'
    } else {
      badgeContainer.innerHTML = levels.map(level => {
        const cls = colorMap[level.toUpperCase()] || "bg-body-secondary"
        return `<span class="${cls} rounded fw-semibold" style="padding: 0.15rem 0.45rem; font-size: 0.72rem; white-space: nowrap; display: inline-block; margin-bottom: 0.1rem;">${this.escapeHtml(level.toUpperCase())}</span>`
      }).join(" ")
    }
  }

  // ── Bulk selection ─────────────────────────────────────────────

  toggleSelectAll() {
    const checked = this.hasSelectAllTarget ? this.selectAllTarget.checked : false
    this.checkboxTargets.forEach(cb => { cb.checked = checked })
    this.updateBulkCount()
  }

  checkboxChanged() {
    this.updateBulkCount()
    // Sync "select all" checkbox
    if (this.hasSelectAllTarget) {
      const total = this.checkboxTargets.length
      const checkedCount = this.checkboxTargets.filter(cb => cb.checked).length
      this.selectAllTarget.checked = checkedCount === total && total > 0
      this.selectAllTarget.indeterminate = checkedCount > 0 && checkedCount < total
    }
  }

  updateBulkCount() {
    const count = this.checkboxTargets.filter(cb => cb.checked).length
    if (this.hasBulkCountTarget) {
      this.bulkCountTarget.textContent = `${count} selected`
    }
  }

  // ── Bulk apply ─────────────────────────────────────────────────

  bulkApply() {
    const controlIds = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => Number.parseInt(cb.value, 10))

    if (controlIds.length === 0) {
      alert("No controls selected")
      return
    }

    const level = this.hasBulkLevelTarget ? this.bulkLevelTarget.value : ""
    const actionType = this.hasBulkActionTarget ? this.bulkActionTarget.value : "add"

    if (!level && actionType !== "set") {
      alert("Please select a baseline level")
      return
    }

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.bulkUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        control_ids: controlIds,
        baseline_level: level,
        action_type: actionType
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Reload to show updated badges (simplest approach for bulk)
        window.location.reload()
      } else {
        alert(data.error || "Bulk update failed")
      }
    })
    .catch(() => alert("Network error — could not apply bulk update"))
  }

  bulkClear() {
    const controlIds = this.checkboxTargets
      .filter(cb => cb.checked)
      .map(cb => Number.parseInt(cb.value, 10))

    if (controlIds.length === 0) {
      alert("No controls selected")
      return
    }

    if (!confirm(`Clear baselines from ${controlIds.length} control(s)?`)) return

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content

    fetch(this.bulkUrlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken,
        "Accept": "application/json"
      },
      body: JSON.stringify({
        control_ids: controlIds,
        baseline_level: "",
        action_type: "set"
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        window.location.reload()
      } else {
        alert(data.error || "Clear failed")
      }
    })
    .catch(() => alert("Network error — could not clear baselines"))
  }

  // ── Helpers ────────────────────────────────────────────────────

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
