import { Controller } from "@hotwired/stimulus"

// Client-side search/filter for converter entry tables.
// Filters rows by matching search text against source_id, target_id,
// category, and remarks columns.
export default class ConverterSearchController extends Controller {
  static targets = ["searchInput", "row", "count", "addRow"]

  connect() {
    this.totalCount = this.rowTargets.length
    this.updateCount(this.totalCount)
  }

  filter() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this._applyFilter(), 150)
  }

  clear() {
    this.searchInputTarget.value = ""
    this._applyFilter()
  }

  _applyFilter() {
    const query = this.searchInputTarget.value.trim().toLowerCase()
    let visible = 0

    this.rowTargets.forEach((row) => {
      if (!query) {
        row.style.display = ""
        visible++
        return
      }

      const text = row.textContent.toLowerCase()
      const match = text.includes(query)
      row.style.display = match ? "" : "none"
      if (match) visible++
    })

    this.updateCount(visible)
  }

  updateCount(visible) {
    if (!this.hasCountTarget) return
    if (visible === this.totalCount) {
      this.countTarget.textContent = `Mapping Entries (${this.totalCount.toLocaleString()})`
    } else {
      this.countTarget.textContent = `Mapping Entries (showing ${visible.toLocaleString()} of ${this.totalCount.toLocaleString()})`
    }
  }
}
