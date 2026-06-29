import { Controller } from "@hotwired/stimulus"

// Applies the operator-defined environment-header colors via the CSSOM so
// they are NOT subject to the CSP style-src directive — this keeps the header
// working if/when 'unsafe-inline' is dropped from style-src (#528). The CSS
// class `.sparc-env-header` provides the brand-default appearance so default
// deployments render correctly before/without this controller (no flash of
// unstyled content); these values only override it.
//
// Color values are validated server-side (SparcConfig.safe_header_color)
// before reaching these data attributes.
//
// Usage (in layouts):
//   <div data-controller="environment-header"
//        data-environment-header-text-color-value="#ffffff"
//        data-environment-header-highlight-color-value="#1f6fa5">…</div>
export default class extends Controller {
  static values = { textColor: String, highlightColor: String }

  connect() {
    if (this.hasTextColorValue && this.textColorValue) {
      this.element.style.color = this.textColorValue
    }
    if (this.hasHighlightColorValue && this.highlightColorValue) {
      this.element.style.backgroundColor = this.highlightColorValue
    }
  }
}
