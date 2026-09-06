import { Controller } from "@hotwired/stimulus"
import { setVisible } from "controllers/visibility"

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

    // #1047 — visibility through the CLASS, not the style attribute.
    //
    // This used to reveal with `row.style.display = ""`, which only works while
    // the row's hidden state IS an inline style. The sweep moves those into
    // `.sparc-d-none`, and clearing an inline display cannot override a class —
    // so every filtered-out row would have stayed hidden for good. setVisible
    // toggles the class and clears any legacy inline display on the way past.
    this.rowTargets.forEach((row) => {
      const match = !query || row.textContent.toLowerCase().includes(query)
      setVisible(row, match)
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
