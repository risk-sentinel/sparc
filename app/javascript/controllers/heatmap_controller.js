import { Controller } from "@hotwired/stimulus"
import { setVisible } from "controllers/visibility"

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
export default class HeatmapController extends Controller {
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
    this.groupOpenStateCaptured = false

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

  // Action: click anywhere on a heatmap card body (delegates to family filter).
  // Skips if the click landed on a badge or family link that has its own handler.
  filterByCard(event) {
    if (event.target.closest("[data-action*='heatmap#filterByCell']") ||
        event.target.closest("[data-action*='heatmap#filterByFamily']")) {
      return
    }
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

  // Action: server-mode card click — navigate to the card's filter URL.
  // Replaces an inline onclick (#647, epic #650); ignores clicks that land on
  // a nested <a> so the family link still works.
  navigateByHref(event) {
    if (event.target.closest("a")) return
    const href = event.currentTarget.dataset.href
    if (href) window.location.href = href
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
      const groups = container.querySelectorAll("details.sparc-family-group")
      groups.forEach(group => {
        group.style.display = ""
        this.updateGroupCount(group, null)
      })
      this.restoreGroupOpenState(groups)
    }

    this.badgeTargets.forEach(el => {
      el.style.opacity = "1"
      el.style.outline = "none"
    })

    this.chipTargets.forEach(el => {
      el.style.background = ""
    })

    if (this.hasBannerTarget) {
      setVisible(this.bannerTarget, false)
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
      const groups = container.querySelectorAll("details.sparc-family-group")
      const filtering = Boolean(this.activeFamily || this.activeFilter)
      if (filtering) this.captureGroupOpenState(groups)

      // Tally the matches per family group while filtering the cards, so the
      // group decisions below read a real count instead of re-deriving
      // visibility from the serialized style attribute.
      const matchesPerGroup = new Map()
      container.querySelectorAll(".control-card").forEach(card => {
        const familyMatch = !this.activeFamily || card.dataset.family === this.activeFamily
        const filterMatch = !this.activeFilter || this.cardMatchesFilter(card, this.activeFilter)
        const show = familyMatch && filterMatch
        card.style.display = show ? "" : "none"
        if (!show) return
        visible++
        const group = card.closest("details.sparc-family-group")
        if (group) matchesPerGroup.set(group, (matchesPerGroup.get(group) || 0) + 1)
      })

      groups.forEach(group => {
        const matches = matchesPerGroup.get(group) || 0
        // Hide family group wrappers that have no visible cards
        group.style.display = matches > 0 ? "" : "none"
        // A group that survives the filter must not hide its matches behind a
        // collapsed <details>. These groups render closed, so without this a
        // deep link like ?family=CM&status=Deferred lands on a page whose
        // matching rows are all sealed inside a collapsed summary.
        if (filtering && matches > 0) group.open = true
        this.updateGroupCount(group, filtering ? matches : null)
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
        setVisible(this.bannerTarget, true)
      } else {
        setVisible(this.bannerTarget, false)
      }
    }

    this.updateAriaStates()
    this.syncUrl()
  }

  // Returns true if the card matches the active filter value.
  // For SAP cards, data-methods (plural) holds the full comma-separated list of
  // methods, so a multi-method control matches each of its individual methods
  // AND the synthetic "multiple" filter. Cards without data-methods fall back
  // to strict equality on data-{filterKey} (existing behavior for POAM/SAR/SSP).
  cardMatchesFilter(card, filter) {
    const methodsAttr = card.dataset.methods
    if (typeof methodsAttr === "string") {
      const methods = methodsAttr.split(",").map(s => s.trim()).filter(Boolean)
      if (filter === "multiple") return methods.length > 1
      if (filter === "(none)" || filter === "(None)") return methods.length === 0
      return methods.includes(filter)
    }
    return card.dataset[this.filterKeyValue] === filter
  }

  // The family summary badge is server-rendered with that group's unfiltered
  // total. Show "<matches> / <total>" while a filter narrows the group and the
  // bare total otherwise, so the header can never contradict the rows under it.
  updateGroupCount(group, matches) {
    const badge = group.querySelector("[data-heatmap-count]")
    if (!badge) return
    const total = badge.dataset.heatmapCount
    badge.textContent = (matches === null || String(matches) === total)
      ? total
      : `${matches} / ${total}`
  }

  // Remember how the user had the groups expanded before the first filter of a
  // run, so clear() restores that rather than leaving every group forced open.
  captureGroupOpenState(groups) {
    if (this.groupOpenStateCaptured) return
    groups.forEach(group => { group.dataset.heatmapPrevOpen = group.open ? "1" : "0" })
    this.groupOpenStateCaptured = true
  }

  restoreGroupOpenState(groups) {
    if (!this.groupOpenStateCaptured) return
    groups.forEach(group => {
      if (group.dataset.heatmapPrevOpen !== undefined) {
        group.open = group.dataset.heatmapPrevOpen === "1"
        delete group.dataset.heatmapPrevOpen
      }
    })
    this.groupOpenStateCaptured = false
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
