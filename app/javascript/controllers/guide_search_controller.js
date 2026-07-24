import { Controller } from "@hotwired/stimulus"

// Client-side filter for the Help Center guide grid (#784). Matches the query
// against each card's title + summary (stored in data attributes) and toggles
// card visibility. Fully offline — no backend search request.
export default class GuideSearchController extends Controller {
  static targets = ["query", "card", "empty"]

  filter() {
    clearTimeout(this._debounce)
    this._debounce = setTimeout(() => this._apply(), 120)
  }

  _apply() {
    const query = this.queryTarget.value.trim().toLowerCase()
    let visible = 0

    this.cardTargets.forEach((card) => {
      const haystack = `${card.dataset.guideTitle || ""} ${card.dataset.guideSummary || ""}`
      const match = !query || haystack.includes(query)
      card.classList.toggle("d-none", !match)
      if (match) visible++
    })

    if (this.hasEmptyTarget) {
      this.emptyTarget.classList.toggle("d-none", visible !== 0)
    }
  }
}
