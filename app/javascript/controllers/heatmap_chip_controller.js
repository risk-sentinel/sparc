import { Controller } from "@hotwired/stimulus"

// Dispatches a "heatmap:chip" filter event to the heatmap section when a status/
// severity/priority chip is clicked (#647, epic #650). Replaces the inline
// onclick handlers (SSP/SAP/CDEF/Profile) — which built a CustomEvent inline and
// were blocked by strict CSP. The filter value is passed as a Stimulus action
// param (data-heatmap-chip-filter-param) instead of being interpolated into JS.
export default class HeatmapChipController extends Controller {
  apply(event) {
    // Chips are bound to keydown.space as well as click. Without this, Space
    // activates the filter AND scrolls the page — the chips are <div
    // role="button">, so the browser still applies its default scroll
    // behavior. Harmless on click (a div has no default action).
    event.preventDefault()

    const section = document.getElementById("heatmapSection")
    if (section) {
      section.dispatchEvent(
        new CustomEvent("heatmap:chip", { detail: { filter: event.params.filter } })
      )
    }
  }
}
