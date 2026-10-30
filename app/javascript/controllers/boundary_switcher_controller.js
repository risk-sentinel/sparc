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
      if (!this.panelTarget.hidden && !this.element.contains(event.target)) this.close(false)
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
    this.panelTarget.hidden ? this.open() : this.close(true)
  }

  open() {
    this.panelTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.filterTarget.focus()
  }

  close(returnFocus) {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
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
    if (this.panelTarget.hidden) return

    if (event.key === "Escape") {
      event.preventDefault()
      this.close(true)
      return
    }

    const items = this.visibleItems()
    if (items.length === 0) return
    const index = items.indexOf(document.activeElement)
    let next = null
    if (event.key === "ArrowDown") next = index < 0 ? 0 : Math.min(index + 1, items.length - 1)
    else if (event.key === "ArrowUp") next = index <= 0 ? null : index - 1
    else if (event.key === "Home" && index >= 0) next = 0
    else if (event.key === "End" && index >= 0) next = items.length - 1
    else return

    event.preventDefault()
    if (next === null) this.filterTarget.focus()
    else items[next].focus()
  }

  visibleItems() {
    return this.itemTargets.filter((item) => !item.closest("li").hidden)
  }
}
