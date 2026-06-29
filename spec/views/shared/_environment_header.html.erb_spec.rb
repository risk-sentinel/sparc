# frozen_string_literal: true

require "rails_helper"

# Issue #682 — configurable environment/rules header bar shown on every
# screen. The text is escaped plain text (special-char / XSS safe); colors
# are operator-defined, validated, and applied via the CSSOM (data-* values
# consumed by environment_header_controller) so they are not subject to CSP
# style-src. NIST AC-8 (System Use Notification).
RSpec.describe "shared/_environment_header.html.erb", type: :view do
  around do |ex|
    saved = %w[SPARC_HEADER_TEXT SPARC_HEADER_TEXT_COLOR SPARC_HEADER_HIGHLIGHT_COLOR]
            .index_with { |k| ENV[k] }
    ex.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  context "when SPARC_HEADER_TEXT is unset" do
    it "renders nothing" do
      ENV.delete("SPARC_HEADER_TEXT")
      render partial: "shared/environment_header"
      expect(rendered.strip).to be_empty
    end
  end

  context "when SPARC_HEADER_TEXT is set" do
    before { ENV["SPARC_HEADER_TEXT"] = "PRODUCTION — Authorized use only" }

    it "renders the header text wired to the Stimulus controller" do
      render partial: "shared/environment_header"
      expect(rendered).to include("PRODUCTION — Authorized use only")
      expect(rendered).to include(%(data-controller="environment-header"))
      expect(rendered).to include(%(aria-label="Environment notice"))
    end

    it "applies the default WCAG-AA brand colors via data values" do
      ENV.delete("SPARC_HEADER_TEXT_COLOR")
      ENV.delete("SPARC_HEADER_HIGHLIGHT_COLOR")
      render partial: "shared/environment_header"
      expect(rendered).to include(%(data-environment-header-text-color-value="#ffffff"))
      expect(rendered).to include(%(data-environment-header-highlight-color-value="#1f6fa5"))
    end

    it "passes valid operator colors through" do
      ENV["SPARC_HEADER_TEXT_COLOR"]      = "#0B1F2A"
      ENV["SPARC_HEADER_HIGHLIGHT_COLOR"] = "rgb(138, 109, 0)"
      render partial: "shared/environment_header"
      expect(rendered).to include(%(data-environment-header-text-color-value="#0B1F2A"))
      expect(rendered).to include(%(data-environment-header-highlight-color-value="rgb(138, 109, 0)"))
    end

    it "escapes HTML/special characters in the text (no raw markup)" do
      ENV["SPARC_HEADER_TEXT"] = %q{<script>alert('xss')</script> & "quotes" ☣}
      render partial: "shared/environment_header"
      expect(rendered).not_to include("<script>alert")
      expect(rendered).to include("&lt;script&gt;")
      expect(rendered).to include("☣")
    end

    it "falls back to default colors when operator values are malformed" do
      ENV["SPARC_HEADER_TEXT_COLOR"]      = "red; background:url(x)"
      ENV["SPARC_HEADER_HIGHLIGHT_COLOR"] = "</div><script>"
      render partial: "shared/environment_header"
      expect(rendered).to include(%(data-environment-header-text-color-value="#ffffff"))
      expect(rendered).to include(%(data-environment-header-highlight-color-value="#1f6fa5"))
      expect(rendered).not_to include("<script>")
    end
  end
end
