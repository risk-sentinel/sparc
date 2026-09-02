# frozen_string_literal: true

require "rails_helper"

# #1047 — the ratchet that keeps the inline-style sweep swept.
#
# Removing `style-src 'unsafe-inline'` is one line; SURVIVING its removal is
# ~1,400 edits, and the failure mode is silent — an inline style simply stops
# applying, with no console error, no exception and no failing spec. So the sweep
# needs two things the repo did not have: a way to see breakage (the visual
# regression harness, tests/ui-smoke/visual_regression_1047.py) and a way to stop
# the problem growing back. This is the second.
#
# It is a RATCHET, not a target. The number may only ever go DOWN. A new inline
# style fails this spec and the author is pointed at the theme, which is the
# whole point: one-off inline styles are how a design system rots.
RSpec.describe "inline style= in views (#1047 ratchet)", type: :view do
  # NOT a top-level constant — a spec's top-level constant is global and leaks
  # into every other spec in the suite.
  let(:view_root) { Rails.root.join("app/views") }

  # Lower this with every slice. Never raise it.
  #
  # Measured 2026-09-01 on the Bundle Z branch point: 1,403 attributes across
  # 115 files, of which 1,361 are static (no ERB interpolation) and 42 are
  # dynamic. Phase 2 slice 1 took sar_documents/enrich.html.erb from 136 to 0,
  # verified against all 78 baseline screens with zero pixels changed. The static ones become theme utilities; the dynamic ones become
  # data-* attributes applied by a Stimulus controller, because a style set from
  # JavaScript is not what `style-src` blocks.
  let(:ceiling) { 1070 }

  def inline_styles
    Dir.glob(view_root.join("**/*.erb")).flat_map do |path|
      File.read(path).scan(/style="[^"]*"/).map { |m| [ path, m ] }
    end
  end

  it "never grows — a new inline style belongs in sparc-theme.css" do
    found = inline_styles

    expect(found.length).to be <= ceiling,
      "inline style= count rose to #{found.length}, ceiling is #{ceiling}.\n" \
      "#1047 is removing these: style-src 'unsafe-inline' is going away, and an " \
      "inline style will simply STOP APPLYING with no error.\n" \
      "Put the declaration in app/assets/stylesheets/sparc-theme.css as a " \
      "`sparc-`-prefixed class and use that instead. If the value is computed, " \
      "pass it as a data-* attribute and set it from a Stimulus controller."
  end

  it "reports when the ceiling is stale, so the ratchet actually ratchets" do
    found = inline_styles.length

    # Not a failure — a nudge. A ceiling left high after a slice lands would let
    # the count creep back up to it unnoticed, which defeats the mechanism.
    if found < ceiling
      warn "[#1047] inline style= is down to #{found}; lower the ceiling in " \
           "#{__FILE__.sub(Rails.root.to_s + '/', '')} from #{ceiling} to #{found}."
    end

    expect(found).to be <= ceiling
  end
end
