import { Controller } from "@hotwired/stimulus"

// #880 — in-page help drawer.
//
// #870 made help non-destructive by opening guides in a new tab. That is right
// for a guide you intend to READ, but a quick lookup ("what goes in this
// field?") still costs a context switch. This slides the guide over the current
// screen instead, leaving the part-filled form visible underneath.
//
// The drawer complements the new tab rather than replacing it: the anchor keeps
// its href/target, so if this controller never connects (JS error, asset
// failure) the "?" is still a working link to the guide. `preventDefault` only
// happens once we know we can handle it.
//
// No inline handlers anywhere — CSP has no 'unsafe-inline' (see #650).
export default class extends Controller {
  static targets = ["drawer", "frame", "fullGuide"]

  connect() {
    // Bound once so the listener can be removed by identity in disconnect().
    this.teardownBeforeRender = this.teardownBeforeRender.bind(this)
    this.restoreFocus = this.restoreFocus.bind(this)

    // Two hooks, because they catch two different strandings.
    //
    // turbo:before-render — tear down before the swap rather than after.
    //
    // turbo:before-cache — Turbo snapshots the CURRENT body before rendering
    // the next page, so before-render fires too late to keep an open drawer
    // out of that snapshot. Coming Back then restores a page with the panel
    // still shown and `overflow: hidden` still on the body: a screen that
    // looks frozen with nothing visible to blame. I did observe exactly that
    // while building this, but only intermittently — see the caveat below.
    //
    // Both hooks are cheap insurance rather than proven necessities. SPARC
    // sets `turbo-cache-control: no-cache` app-wide in the layout, so no
    // snapshot is ever taken and neither hook can be caught failing by a test
    // (tests/ui-smoke/test_help_drawer_880.py documents the attempt). That
    // meta is one line in a layout, and this control should not quietly
    // depend on it staying there.
    document.addEventListener("turbo:before-render", this.teardownBeforeRender)
    document.addEventListener("turbo:before-cache", this.teardownBeforeRender)

    if (this.hasDrawerTarget) {
      this.drawerTarget.addEventListener("hidden.bs.offcanvas", this.restoreFocus)
    }
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.teardownBeforeRender)
    document.removeEventListener("turbo:before-cache", this.teardownBeforeRender)

    if (this.hasDrawerTarget) {
      this.drawerTarget.removeEventListener("hidden.bs.offcanvas", this.restoreFocus)
    }

    this.dispose()
  }

  // Click on the navbar "?" (or any control pointing at a guide).
  open(event) {
    if (!window.bootstrap || !this.hasDrawerTarget || !this.hasFrameTarget) return

    const trigger = event.currentTarget
    const href = trigger.getAttribute("href")
    if (!href) return

    // Resolve the frame URL BEFORE claiming the click. A guide we cannot load
    // same-origin has to stay a plain link rather than becoming a dead "?".
    const src = this.drawerSrcFor(href)
    if (!src) return

    // Only now do we own the click. Before this point the anchor's own
    // behaviour (new tab) is the fallback and must be left alone.
    event.preventDefault()

    // Focus has to come back here on close — a keyboard user who opened the
    // drawer from the navbar must not be dumped at the top of the document.
    this.returnFocusTo = trigger

    // The full-guide escape hatch points at the same guide the drawer shows,
    // so "open the whole thing in a tab" is never a different page.
    if (this.hasFullGuideTarget) this.fullGuideTarget.setAttribute("href", href)

    // Setting src is what fetches the frame. Re-setting the same value does
    // not re-fetch, so a second open of the same guide reuses what is loaded.
    if (this.frameTarget.getAttribute("src") !== src) {
      this.frameTarget.setAttribute("src", src)
    }

    // The focus trap is what keeps Tab from walking out of the dialog and into
    // the form underneath. Bootstrap arms it when `!scroll || backdrop`, so it
    // survives either option being flipped alone — measured: scroll:true on
    // its own changes nothing. Turning BOTH off disarms it, which is why they
    // are pinned together here rather than left to the defaults.
    this.offcanvas().show()
  }

  // Bootstrap focuses the panel on show and handles Esc itself, but it does
  // NOT return focus to the element that opened it.
  restoreFocus() {
    const trigger = this.returnFocusTo
    this.returnFocusTo = null
    // isConnected guards the case where the trigger was removed while open.
    if (trigger && trigger.isConnected) trigger.focus()
  }

  teardownBeforeRender() {
    this.dispose()
  }

  offcanvas() {
    return window.bootstrap.Offcanvas.getOrCreateInstance(this.drawerTarget, {
      scroll: false,
      backdrop: true,
      keyboard: true
    })
  }

  dispose() {
    if (!window.bootstrap || !this.hasDrawerTarget) return

    const instance = window.bootstrap.Offcanvas.getInstance(this.drawerTarget)
    if (instance) {
      // hide() before dispose() so Bootstrap removes its backdrop and unlocks
      // body scroll. dispose() alone leaves both behind.
      instance.hide()
      instance.dispose()
    }

    // hide() animates, and Turbo takes its snapshot synchronously — so at
    // cache time the panel can still be mid-transition with `.show` on it and
    // the body still scroll-locked. Asking Bootstrap nicely is not enough
    // here; the closed state has to be true NOW, not one transition from now.
    // Correct by construction rather than by measurement: the race is real
    // but does not reproduce on demand, so no test pins this.
    this.drawerTarget.classList.remove("show", "showing")
    document.querySelectorAll(".offcanvas-backdrop").forEach((el) => el.remove())
    document.body.style.removeProperty("overflow")
    document.body.style.removeProperty("padding-right")
  }

  // /help/evidence-and-attestations -> /help/evidence-and-attestations?drawer=1
  //
  // Built with URL against the current origin so a value that is not a
  // same-origin path cannot become the frame's src.
  drawerSrcFor(href) {
    const url = new URL(href, window.location.origin)
    if (url.origin !== window.location.origin) return null

    url.searchParams.set("drawer", "1")
    return url.pathname + url.search
  }
}
