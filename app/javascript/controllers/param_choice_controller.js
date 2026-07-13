import { Controller } from "@hotwired/stimulus"

// Wires the ODP parameter-suggestion badges to the existing
// window.sparc.pickParamChoice helper without an inline onclick (#647, #650).
// Reuses the already-tested global logic rather than duplicating it; the only
// change is moving the trigger off a CSP-blocked on* attribute onto data-action.
export default class ParamChoiceController extends Controller {
  pick(event) {
    window.sparc?.pickParamChoice?.(event.currentTarget)
  }
}
