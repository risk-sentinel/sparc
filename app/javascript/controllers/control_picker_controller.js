import { Controller } from "@hotwired/stimulus"

/**
 * Catalog-backed control picker (#902 follow-up).
 *
 * Replaces a free-text "Control IDs" box. That field let a user type anything,
 * and anything is what got stored: a typo linked evidence to a control in no
 * catalog, and — far more commonly — SPARC *displays* the padded form (AC-02)
 * while catalogs *store* the canonical one (ac-2), so copying the identifier
 * off the screen produced a link that matched nothing. Silently. Every seeded
 * evidence link was dead this way.
 *
 * So the user searches real controls and picks from results. What is submitted
 * is always a canonical identifier that exists — enhancements (ac-2.1) very
 * much included, since an enhancement is a control in its own right.
 *
 * Typing is still allowed: with 4,000+ controls a dropdown is unusable, and
 * pasting a list of ids from a spreadsheet is a real workflow. A typed token is
 * resolved against the catalog before it becomes a chip, and rejected visibly
 * if it names nothing. The server validates independently — this is the
 * convenience, not the guarantee.
 */
export default class ControlPickerController extends Controller {
  static targets = ["search", "hidden", "chips", "results", "status"]
  static values = {
    url: String,
    boundaryId: String,
    // Canonical ids already linked, rendered as chips on load.
    selected: Array
  }

  static DEBOUNCE_MS = 200

  connect() {
    this.selected = new Map()
    ;(this.selectedValue || []).forEach((c) => {
      this.selected.set(c.control_id, c)
    })
    this.renderChips()
    this.syncHidden()
    this.activeIndex = -1
    this.results = []
  }

  disconnect() {
    clearTimeout(this.debounce)
    if (this.controller) this.controller.abort()
  }

  // ── Search ───────────────────────────────────────────────────────

  search() {
    clearTimeout(this.debounce)
    const term = this.searchTarget.value.trim()

    if (term.length < 2) {
      this.closeResults()
      return
    }

    this.debounce = setTimeout(() => this.fetchResults(term), this.constructor.DEBOUNCE_MS)
  }

  async fetchResults(term) {
    // A slow response for an old keystroke must not overwrite a newer one.
    if (this.controller) this.controller.abort()
    this.controller = new AbortController()

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", term)
    if (this.boundaryIdValue) {
      url.searchParams.set("authorization_boundary_id", this.boundaryIdValue)
    }

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: this.controller.signal
      })
      if (!response.ok) throw new Error(`lookup failed (HTTP ${response.status})`)

      const body = await response.json()
      this.results = body.data || []
      this.renderResults(body.meta || {})
    } catch (error) {
      if (error.name === "AbortError") return
      // Never fail silently — that is the whole point of #902.
      this.setStatus(
        `Could not search controls (${error.message}). You can still type an identifier; it will be checked when you save.`,
        true
      )
      this.closeResults()
    }
  }

  // ── Selection ────────────────────────────────────────────────────

  choose(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.controlId
    const control = this.results.find((c) => c.control_id === id)
    if (control) this.add(control)
  }

  add(control) {
    if (!this.selected.has(control.control_id)) {
      this.selected.set(control.control_id, control)
      this.renderChips()
      this.syncHidden()
    }
    this.searchTarget.value = ""
    this.closeResults()
    this.setStatus(`${control.display_id} added.`)
    this.searchTarget.focus()
  }

  remove(event) {
    event.preventDefault()
    const id = event.currentTarget.dataset.controlId
    const control = this.selected.get(id)
    this.selected.delete(id)
    this.renderChips()
    this.syncHidden()
    if (control) this.setStatus(`${control.display_id} removed.`)
  }

  // ── Keyboard ─────────────────────────────────────────────────────

  keydown(event) {
    if (event.key === "Escape") {
      this.closeResults()
      return
    }

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      if (!this.results.length) return
      event.preventDefault()
      const delta = event.key === "ArrowDown" ? 1 : -1
      this.activeIndex = (this.activeIndex + delta + this.results.length) % this.results.length
      this.highlight()
      return
    }

    if (event.key === "Enter") {
      // Never let Enter in the search box submit the evidence form — the user
      // is picking a control, not saving.
      event.preventDefault()
      if (this.activeIndex >= 0 && this.results[this.activeIndex]) {
        this.add(this.results[this.activeIndex])
      } else if (this.searchTarget.value.trim()) {
        this.resolveTyped(this.searchTarget.value.trim())
      }
    }
  }

  // A typed or pasted identifier is checked against the catalog before it can
  // become a chip. Accepts any of the three legitimate forms.
  async resolveTyped(raw) {
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("q", raw)
    url.searchParams.set("limit", "5")

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const body = await response.json()
      const exact = (body.data || []).find(
        (c) =>
          c.control_id.toLowerCase() === raw.toLowerCase() ||
          c.padded_id.toLowerCase() === raw.toLowerCase() ||
          c.display_id.toLowerCase() === raw.toLowerCase()
      )

      if (exact) {
        this.add(exact)
      } else {
        this.setStatus(
          `"${raw}" does not match a control in any loaded catalog. Search for one instead.`,
          true
        )
      }
    } catch {
      this.setStatus(`Could not check "${raw}". It will be validated when you save.`, true)
    }
  }

  // ── Rendering ────────────────────────────────────────────────────

  renderResults(meta) {
    this.activeIndex = -1
    this.resultsTarget.innerHTML = ""

    if (!this.results.length) {
      this.resultsTarget.appendChild(
        this.element_("div", "sparc-control-picker__empty", "No matching controls.")
      )
      this.setExpanded(true)
      return
    }

    if (meta.scoped_to_profile && meta.profile_title) {
      this.resultsTarget.appendChild(
        this.element_(
          "div",
          "sparc-control-picker__scope",
          `Showing this system's baseline: ${meta.profile_title}`
        )
      )
    }

    this.results.forEach((control, index) => {
      const row = document.createElement("button")
      row.type = "button"
      row.className = "sparc-control-picker__option"
      row.dataset.controlId = control.control_id
      row.dataset.index = String(index)
      row.dataset.action = "click->control-picker#choose"
      row.setAttribute("role", "option")
      // aria-activedescendant references an option by id, so every option needs
      // one — without it, arrow-key navigation moves a visual highlight that no
      // screen reader ever announces.
      row.id = `evidence_control_option_${index}`
      row.setAttribute("aria-selected", "false")

      const id = this.element_("span", "sparc-control-picker__option-id", control.display_id)
      if (control.enhancement) id.classList.add("sparc-control-picker__option-id--enhancement")
      row.appendChild(id)
      row.appendChild(
        this.element_("span", "sparc-control-picker__option-title", control.title || "")
      )
      if (control.family_code) {
        row.appendChild(
          this.element_("span", "sparc-control-picker__option-family", control.family_code)
        )
      }
      this.resultsTarget.appendChild(row)
    })

    this.setExpanded(true)
  }

  // Keeps the input's advertised state and the list's actual state in step.
  // These were markup-only before, so they never changed after first render.
  setExpanded(open) {
    this.resultsTarget.hidden = !open
    this.searchTarget.setAttribute("aria-expanded", open ? "true" : "false")
    if (!open) this.searchTarget.removeAttribute("aria-activedescendant")
  }

  highlight() {
    let active = null
    this.resultsTarget
      .querySelectorAll(".sparc-control-picker__option")
      .forEach((el, i) => {
        const on = i === this.activeIndex
        el.classList.toggle("is-active", on)
        el.setAttribute("aria-selected", on ? "true" : "false")
        if (on) active = el
      })

    if (active) {
      this.searchTarget.setAttribute("aria-activedescendant", active.id)
    } else {
      this.searchTarget.removeAttribute("aria-activedescendant")
    }
  }

  renderChips() {
    this.chipsTarget.innerHTML = ""

    if (this.selected.size === 0) {
      this.chipsTarget.appendChild(
        this.element_(
          "span",
          "sparc-control-picker__none",
          "No controls linked yet."
        )
      )
      return
    }

    this.selected.forEach((control, id) => {
      const chip = this.element_("span", "sparc-control-picker__chip")
      // A link stored before validation existed may name nothing. It is shown
      // rather than dropped — silently discarding it on render would delete it
      // on the next save, turning a visible problem into data loss.
      if (control.unresolved) chip.classList.add("sparc-control-picker__chip--unresolved")
      chip.appendChild(
        this.element_("span", "sparc-control-picker__chip-id", control.display_id || id)
      )

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "sparc-control-picker__chip-remove"
      remove.dataset.controlId = id
      remove.dataset.action = "click->control-picker#remove"
      remove.setAttribute("aria-label", `Remove ${control.display_id || id}`)
      remove.textContent = "×"
      chip.appendChild(remove)

      this.chipsTarget.appendChild(chip)
    })
  }

  // The hidden field is what the form actually posts: canonical ids only.
  syncHidden() {
    this.hiddenTarget.value = Array.from(this.selected.keys()).join(",")
  }

  closeResults() {
    this.setExpanded(false)
    this.resultsTarget.innerHTML = ""
    this.results = []
    this.activeIndex = -1
  }

  setStatus(message, isError = false) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("text-danger", isError)
    this.statusTarget.classList.toggle("text-body-secondary", !isError)
  }

  element_(tag, className, text) {
    const el = document.createElement(tag)
    el.className = className
    if (text !== undefined) el.textContent = text
    return el
  }
}
