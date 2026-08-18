import { Controller } from "@hotwired/stimulus"

// #948 — remember which tiers a user collapsed, the way the card/list toggle
// remembers its mode.
//
// PERSISTENCE ONLY. The tiers are native <details>, so opening and closing
// works with no JavaScript; this restores the previous choice and records the
// next one. If the controller never loads, the screen is fully usable and
// simply forgets — which is the right failure mode for a display preference.
//
// localStorage rather than a cookie: this is per-browser display state that the
// server never reads, and sending a growing list of collapsed tier keys on
// every request would be waste. (CollectionViewable uses a cookie for view mode
// precisely because the SERVER needs it to pick a template.)
//
// Keys are scoped per screen, so collapsing an organization on /evidences does
// not collapse it on /ssp_documents — a user narrowing one screen has said
// nothing about another.
export default class TierCollapseController extends Controller {
  static targets = ["tier"]
  static values = { screen: String }

  connect() {
    this.tierTargets.forEach((tier) => {
      const stored = this.read(tier.dataset.tierKey)
      if (stored !== null) tier.open = stored
    })
  }

  remember(event) {
    const tier = event.target
    if (!tier.dataset.tierKey) return
    this.write(tier.dataset.tierKey, tier.open)
  }

  storageKey(tierKey) {
    return `sparc_tier_${this.screenValue}_${tierKey}`
  }

  read(tierKey) {
    try {
      const raw = window.localStorage.getItem(this.storageKey(tierKey))
      return raw === null ? null : raw === "true"
    } catch {
      // Private browsing, or storage disabled. Forgetting is acceptable here;
      // breaking the screen is not.
      return null
    }
  }

  write(tierKey, open) {
    try {
      window.localStorage.setItem(this.storageKey(tierKey), String(open))
    } catch {
      // See read().
    }
  }
}
