import { Controller } from "@hotwired/stimulus"
import { isVisible } from "controllers/visibility"

// #629 — multi-row selection + show/hide bulk-action bar for index tables.
//
// Markup contract (wrap the bar + table in the controller element):
//   <div data-controller="bulk-select">
//     <div data-bulk-select-target="bar" hidden> ... bulk action form ...
//       <button data-bulk-select-target="submit">Delete (<span data-bulk-select-target="count">0</span>)</button>
//     </div>
//     <input type="checkbox" data-bulk-select-target="selectAll" data-action="bulk-select#toggleAll">
//     <input type="checkbox" name="ids[]" value="N" form="<bulkFormId>"
//            data-bulk-select-target="row" data-action="bulk-select#toggle"> (per row)
//
// Row checkboxes carry name="ids[]" and form="<the bar's form id>", so the
// browser submits all checked ids with the delete request — no JS marshalling.
//
// #1270 — a group's own "select all" (the Profile screen's families):
//   <input type="checkbox" data-group="AC" data-action="bulk-select#toggleGroup">
// selects the rows with the same data-group that are SHOWN, so with a filter
// applied it takes only the rows the filter left.
export default class BulkSelectController extends Controller {
  static targets = ["row", "selectAll", "bar", "count", "submit"]

  connect() {
    this.update()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.selectableRows.forEach((cb) => { cb.checked = checked })
    this.update()
  }

  toggle() {
    this.update()
  }

  toggleGroup(event) {
    const { group } = event.currentTarget.dataset
    const checked = event.currentTarget.checked
    this.selectableRows
      .filter((cb) => cb.dataset.group === group && isVisible(cb.closest(".control-card") || cb))
      .forEach((cb) => { cb.checked = checked })
    this.update()
  }

  clear() {
    this.rowTargets.forEach((cb) => { cb.checked = false })
    this.element.querySelectorAll("[data-action*='bulk-select#toggleGroup']")
      .forEach((cb) => { cb.checked = false })
    this.update()
  }

  update() {
    const n = this.selectedRows.length

    if (this.hasBarTarget) this.barTarget.hidden = n === 0
    if (this.hasCountTarget) this.countTarget.textContent = n
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = n === 0
      const noun = n === 1 ? "item" : "items"
      this.submitTarget.dataset.turboConfirm =
        `Delete ${n} selected ${noun}? This cannot be undone.`
    }

    if (this.hasSelectAllTarget) {
      const total = this.selectableRows.length
      this.selectAllTarget.checked = n > 0 && n === total
      this.selectAllTarget.indeterminate = n > 0 && n < total
    }
  }

  get selectableRows() {
    return this.rowTargets.filter((cb) => !cb.disabled)
  }

  get selectedRows() {
    return this.selectableRows.filter((cb) => cb.checked)
  }
}
