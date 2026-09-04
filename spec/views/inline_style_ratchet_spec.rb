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
  # Slice 6 took cdef_documents/show.html.erb from 47 to 0, reusing the modal
  # trio (.sparc-modal-overlay/-dialog/-eyebrow) that already existed rather
  # than minting duplicates, and routing all five DYNAMIC styles through the
  # vocabulary: three accents, one .sparc-accent-bg, two widths on bar.
  #
  # Slice 5 took poam_documents/show.html.erb from 72 to 0 — the largest file
  # remaining — using the accent vocabulary slice 4 established rather than
  # restating hexes: the item card's status border and all six hero tiles now
  # read `var(--sparc-accent)` from a `.sparc-accent--*` class.
  #
  # Measured 2026-09-01 on the Bundle Z branch point: 1,403 attributes across
  # 115 files, of which 1,361 are static (no ERB interpolation) and 42 are
  # dynamic. Phase 2 slice 1 took sar_documents/enrich.html.erb from 136 to 0,
  # verified against all 78 baseline screens with zero pixels changed. The static ones become theme utilities; the dynamic ones become
  # data-* attributes applied by a Stimulus controller, because a style set from
  # JavaScript is not what `style-src` blocks.
  let(:ceiling) { 861 }

  # A SECOND guard, learned the hard way in slice 4.
  #
  # The conversion is "delete the style attribute, add a class", and the codemod
  # that does it merges into an existing `class="..."` when one sits immediately
  # before the `style=`. On a MULTI-LINE tag it often does not:
  #
  #     <div class="control-card"
  #          data-family="..."
  #          style="border-left: 4px solid <%= c %>;">
  #
  # ...leaves the element with TWO class attributes. The browser honours the
  # FIRST and silently ignores the second, so the converted styling never
  # applies — the exact silent-failure mode this whole sweep exists to avoid,
  # reintroduced by the fix for it. Three were produced in one slice.
  #
  # ERB is masked before scanning: `value="<%= x %>"` contains `>`, so a naive
  # tag regex truncates mid-tag. That is the same trap that made an earlier
  # codemod skip 28 of 136 attributes.
  it "never leaves an element with two class attributes" do
    offenders = Dir.glob(view_root.join("**/*.erb")).flat_map do |path|
      masked = File.read(path).gsub(/<%.*?%>/m, "ERB")
      masked.scan(/<[a-zA-Z][^>]*>/)
            .select { |tag| tag.scan(/\bclass=/).size > 1 }
            .map { |tag| "#{path.sub(Rails.root.to_s + '/', '')}: #{tag.split.join(' ')[0, 110]}" }
    end

    expect(offenders).to be_empty, lambda {
      "#{offenders.size} element(s) carry two class attributes; the browser uses the " \
      "first and drops the second:\n  " + offenders.join("\n  ")
    }
  end

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
