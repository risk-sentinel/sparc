import { Controller } from "@hotwired/stimulus"

// 1.18.0-rf #1291 — the boundary switcher in the shell header.
//
// The list is server-rendered links (shared/_shell_crumbs), so every boundary
// is reachable before this connects. This adds:
//   - open/close from the trigger, closing on Esc or a click outside, with
//     focus back on the trigger
//   - a type-to-filter box (case-insensitive substring of the name); a group
//     heading hides when nothing under it matches
//   - arrow keys between the visible entries, Home/End to the ends
export default class BoundarySwitcherController extends Controller {
  static targets = ["trigger", "panel", "filter", "item", "group", "empty"]

  connect() {
    this.outside = (event) => {
      if (this.panelTarget.open && !this.element.contains(event.target)) this.close(false)
    }
    this.beforeCache = () => this.close(false)
    document.addEventListener("click", this.outside)
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  toggle() {
    this.panelTarget.open ? this.close(true) : this.open()
  }

  open() {
    this.panelTarget.show()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.filterTarget.focus()
  }

  close(returnFocus) {
    if (!this.panelTarget.open) return
    this.panelTarget.close()
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (returnFocus) this.triggerTarget.focus()
  }

  filter() {
    const query = this.filterTarget.value.trim().toLowerCase()
    let shown = 0
    const groupsWithMatches = new Set()
    this.itemTargets.forEach((item) => {
      const match = query === "" || (item.dataset.name || "").includes(query)
      item.closest("li").hidden = !match
      if (match) {
        shown += 1
        if (item.dataset.group) groupsWithMatches.add(item.dataset.group)
      }
    })
    this.groupTargets.forEach((group) => {
      group.hidden = !groupsWithMatches.has(group.dataset.group)
    })
    this.emptyTarget.hidden = shown > 0
  }

  keydown(event) {
    if (!this.panelTarget.open) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close(true)
      return
    }

    const items = this.visibleItems()
    if (items.length === 0) return
    const next = this.nextIndex(event.key, items.indexOf(document.activeElement), items.length)
    if (next === undefined) return

    event.preventDefault()
    if (next === null) this.filterTarget.focus()
    else items[next].focus()
  }

  // Where a key moves focus among `count` items, from `index` (-1 = the filter
  // box): an item index, null for back to the filter box, or undefined when the
  // key does not move focus.
  nextIndex(key, index, count) {
    switch (key) {
      case "ArrowDown": return index < 0 ? 0 : Math.min(index + 1, count - 1)
      case "ArrowUp": return index <= 0 ? null : index - 1
      case "Home": return index >= 0 ? 0 : undefined
      case "End": return index >= 0 ? count - 1 : undefined
      default: return undefined
    }
  }

  visibleItems() {
    return this.itemTargets.filter((item) => !item.closest("li").hidden)
  }
}
