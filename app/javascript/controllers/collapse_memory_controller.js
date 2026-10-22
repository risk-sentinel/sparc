import { Controller } from "@hotwired/stimulus"

// #1251 — remembers which collapsible sections a person keeps open or closed,
// as the sidebar remembers its sections (sidebar_controller.js), generalised:
//
//   * one localStorage entry per `key` value ("sparc_collapse:<key>"), mapping
//     a section body's id to open/closed, so a choice made on one boundary's
//     page applies on every boundary's page;
//   * it restores ONLY section targets inside its own element (the sidebar
//     looks ids up page-wide);
//   * it keeps each toggle's aria-expanded and `collapsed` class in step with
//     what it restores, so assistive technology hears the real state;
//   * a section marked data-collapse-memory-pinned="open" ignores saved state
//     (a Draft boundary always opens Boundary Completeness);
//   * a link to a section on this page (data-action="collapse-memory#reveal"),
//     or arriving at the page with that section's #anchor, opens it.
//
// Collapsing and expanding is Bootstrap's (data-bs-toggle="collapse"); this
// only listens. Storage can be unavailable or throw (private windows, blocked
// site data): the page then renders its server-side defaults and still works.
// The sidebar keeps its own controller and behaviour.
export default class CollapseMemoryController extends Controller {
  static targets = ["section"]
  static values = { key: String }

  connect() {
    this.onShown = (event) => this.record(event, true)
    this.onHidden = (event) => this.record(event, false)
    this.onHashChange = () => this.openFor(window.location.hash)
    // Recorded when the toggle STARTS (show/hide), not when its ~350ms
    // transition ends (shown/hidden): a reload or a link followed inside that
    // window used to lose the choice. Found by the ui-smoke gate.
    this.element.addEventListener("show.bs.collapse", this.onShown)
    this.element.addEventListener("hide.bs.collapse", this.onHidden)
    window.addEventListener("hashchange", this.onHashChange)

    this.restore()
    this.openFor(window.location.hash)
  }

  disconnect() {
    this.element.removeEventListener("show.bs.collapse", this.onShown)
    this.element.removeEventListener("hide.bs.collapse", this.onHidden)
    window.removeEventListener("hashchange", this.onHashChange)
  }

  // A same-page link to a section: open it before the browser scrolls there.
  reveal(event) {
    const href = event.currentTarget.getAttribute("href") || ""
    const hash = href.includes("#") ? href.slice(href.indexOf("#")) : ""
    this.openFor(hash)
  }

  get storageKey() {
    return `sparc_collapse:${this.keyValue}`
  }

  read() {
    try {
      const parsed = JSON.parse(window.localStorage.getItem(this.storageKey) || "{}")
      return parsed && typeof parsed === "object" ? parsed : {}
    } catch {
      return {}
    }
  }

  write(state) {
    try {
      window.localStorage.setItem(this.storageKey, JSON.stringify(state))
    } catch {
      // Storage unavailable: the choice lasts until the page is left.
    }
  }

  restore() {
    const saved = this.read()
    this.sectionTargets.forEach((section) => {
      if (section.dataset.collapseMemoryPinned === "open") {
        section.classList.add("show")
      } else if (Object.prototype.hasOwnProperty.call(saved, section.id)) {
        section.classList.toggle("show", saved[section.id] === true)
      }
      this.sync(section)
    })
  }

  record(event, open) {
    const section = event.target
    if (!this.sectionTargets.includes(section)) return

    const state = this.read()
    state[section.id] = open
    this.write(state)
    // At the start of a toggle the `show` class has not changed yet, so state
    // the toggles from the event rather than from the class.
    this.setToggles(section, open)
  }

  openFor(hash) {
    if (!hash || hash.length < 2) return

    const anchor = document.getElementById(decodeURIComponent(hash.slice(1)))
    if (!anchor || !this.element.contains(anchor)) return

    const section = anchor.closest("[data-collapse-memory-target~='section']") ||
                    anchor.querySelector("[data-collapse-memory-target~='section']")
    if (!section || !this.sectionTargets.includes(section)) return

    section.classList.add("show")
    this.sync(section)
  }

  sync(section) {
    this.setToggles(section, section.classList.contains("show"))
  }

  setToggles(section, open) {
    this.element.querySelectorAll(`[aria-controls="${section.id}"]`).forEach((toggle) => {
      toggle.setAttribute("aria-expanded", String(open))
      toggle.classList.toggle("collapsed", !open)
    })
  }
}
