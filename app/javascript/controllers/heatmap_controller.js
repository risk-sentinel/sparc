import { Controller } from "@hotwired/stimulus"

// Stimulus controller for interactive heatmap filtering.
//
// Place data-controller="heatmap" on the heatmap <details> element.
// The controller finds the controls container by ID (default: "controlsContainer").
// Summary chips outside the controller scope can use
//   data-action="click->heatmap#filterByChip" if the chip is inside a parent
//   that also has the controller, OR chips can be placed inside the controller element.
//
// Values:
//   filter-key       — "status" or "severity" (secondary filter dimension)
//   initial-family   — pre-applied family filter from URL
//   initial-filter   — pre-applied status/severity filter from URL
//   url-sync         — "true" to push filters into the URL
//   container-id     — ID of the controls container element (default: "controlsContainer")
export default class extends Controller {
  static targets = ["badge", "chip", "banner", "bannerLabel"]
  static values = {
    filterKey: { type: String, default: "status" },
    initialFamily: { type: String, default: "" },
    initialFilter: { type: String, default: "" },
    urlSync: { type: Boolean, default: false },
    containerId: { type: String, default: "controlsContainer" }
  }

  connect() {
    this.activeFamily = this.initialFamilyValue || null
    this.activeFilter = this.initialFilterValue || null

    if (this.activeFamily || this.activeFilter) {
      this.applyFilter()
    }

    this.boundKeydown = this.handleKeydown.bind(this)
    this.element.addEventListener("keydown", this.boundKeydown)

    // Listen for chip events dispatched from elements outside the controller scope
    this.boundChipHandler = this.handleChipEvent.bind(this)
    this.element.addEventListener("heatmap:chip", this.boundChipHandler)

    // Toggle section arrow icon when <details> opens/closes
    if (this.element.tagName === "DETAILS") {
      this.element.addEventListener("toggle", () => {
        const icon = this.element.querySelector("#heatmapToggleIcon")
        if (icon) icon.innerHTML = this.element.open ? "\u25BC" : "\u25B6"
      })
    }
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.boundKeydown)
    this.element.removeEventListener("heatmap:chip", this.boundChipHandler)
  }

  handleChipEvent(event) {
    const filter = event.detail.filter
    if (!this.activeFamily && this.activeFilter === filter) {
      this.clear()
    } else {
      this.activeFamily = null
      this.activeFilter = filter
      this.applyFilter()
    }
  }

  // Action: click a badge (family + status/severity)
  filterByCell(event) {
    event.preventDefault()
    const el = event.currentTarget
    const family = el.dataset.family
    const filter = el.dataset[this.filterKeyValue]

    if (this.activeFamily === family && this.activeFilter === filter) {
      this.clear()
    } else {
      this.activeFamily = family
      this.activeFilter = filter
      this.applyFilter()
    }
  }

  // Action: click a family link
  filterByFamily(event) {
    event.preventDefault()
    const family = event.currentTarget.dataset.family

    if (this.activeFamily === family && !this.activeFilter) {
      this.clear()
    } else {
      this.activeFamily = family
      this.activeFilter = null
      this.applyFilter()
    }
  }

  // Action: click a summary chip (filter by status/severity only)
  filterByChip(event) {
    event.preventDefault()
    const filter = event.currentTarget.dataset.filterValue

    if (!this.activeFamily && this.activeFilter === filter) {
      this.clear()
    } else {
      this.activeFamily = null
      this.activeFilter = filter
      this.applyFilter()
    }
  }

  // Action: clear button
  clear() {
    this.activeFamily = null
    this.activeFilter = null

    const container = document.getElementById(this.containerIdValue)
    if (container) {
      container.querySelectorAll(".control-card").forEach(card => {
        card.style.display = ""
      })
    }

    this.badgeTargets.forEach(el => {
      el.style.opacity = "1"
      el.style.outline = "none"
    })

    this.chipTargets.forEach(el => {
      el.style.background = ""
    })

    if (this.hasBannerTarget) {
      this.bannerTarget.style.display = "none"
    }

    this.updateAriaStates()
    this.syncUrl()
  }

  // Keyboard handler
  handleKeydown(event) {
    if (event.key === "Escape") {
      this.clear()
      return
    }

    if (event.key === "Enter" || event.key === " ") {
      const target = event.target
      if (target.matches("[data-action*='heatmap#filterByCell']") ||
          target.matches("[data-action*='heatmap#filterByFamily']") ||
          target.matches("[data-action*='heatmap#filterByChip']")) {
        event.preventDefault()
        target.click()
      }
    }
  }

  // ── Private ──

  applyFilter() {
    let visible = 0

    const container = document.getElementById(this.containerIdValue)
    if (container) {
      container.querySelectorAll(".control-card").forEach(card => {
        const familyMatch = !this.activeFamily || card.dataset.family === this.activeFamily
        const filterAttr = card.dataset[this.filterKeyValue]
        const filterMatch = !this.activeFilter || filterAttr === this.activeFilter
        const show = familyMatch && filterMatch
        card.style.display = show ? "" : "none"
        if (show) visible++
      })
    }

    this.badgeTargets.forEach(el => {
      const familyMatch = !this.activeFamily || el.dataset.family === this.activeFamily
      const filterMatch = !this.activeFilter || el.dataset[this.filterKeyValue] === this.activeFilter
      el.style.opacity = (familyMatch && filterMatch) ? "1" : "0.35"
      el.style.outline = (this.activeFamily && this.activeFilter &&
        el.dataset.family === this.activeFamily &&
        el.dataset[this.filterKeyValue] === this.activeFilter) ? "2px solid #2c3e50" : "none"
    })

    this.chipTargets.forEach(el => {
      el.style.background = (!this.activeFamily && this.activeFilter &&
        el.dataset.filterValue === this.activeFilter) ? "rgba(255,255,255,0.15)" : ""
    })

    if (this.hasBannerTarget && this.hasBannerLabelTarget) {
      if (this.activeFamily || this.activeFilter) {
        let label
        if (this.activeFamily && this.activeFilter) {
          label = this.activeFamily + " \u2022 " + this.activeFilter
        } else {
          label = this.activeFamily || this.activeFilter
        }
        this.bannerLabelTarget.textContent = "Showing: " + label + " \u2014 " + visible + " control(s)"
        this.bannerTarget.style.display = "flex"
      } else {
        this.bannerTarget.style.display = "none"
      }
    }

    this.updateAriaStates()
    this.syncUrl()
  }

  updateAriaStates() {
    this.badgeTargets.forEach(el => {
      const isActive = (this.activeFamily && el.dataset.family === this.activeFamily) &&
        (!this.activeFilter || el.dataset[this.filterKeyValue] === this.activeFilter)
      el.setAttribute("aria-pressed", isActive ? "true" : "false")
    })
  }

  syncUrl() {
    if (!this.urlSyncValue) return

    const url = new URL(window.location)
    if (this.activeFamily) {
      url.searchParams.set("family", this.activeFamily)
    } else {
      url.searchParams.delete("family")
    }
    if (this.activeFilter) {
      url.searchParams.set(this.filterKeyValue, this.activeFilter)
    } else {
      url.searchParams.delete(this.filterKeyValue)
    }

    history.replaceState(null, "", url.toString())
  }
}
