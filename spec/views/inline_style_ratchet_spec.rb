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
  # Slice 9 took control_catalogs/import.html.erb from 34 to 0 and introduced the
  # first SURFACE tokens: --sparc-ink / --sparc-ink-deep. Those two navies were
  # hand-written 25 times across both stylesheets and the views with no name;
  # the gradients, the filter banner, the control-id text and this screen's code
  # blocks had each picked them independently.
  #
  # Slice 8 took control_families/show.html.erb from 43 to 0, and needed three
  # things done FIRST rather than as part of the conversion: the screen was
  # absent from the visual gate entirely (LINK_FROM_SHOW now reaches it),
  # `baseline_editor` revealed elements by writing an EMPTY inline display —
  # which a class cannot be overridden by — and nothing clicked the toggle.
  #
  # Slice 7 took sar_documents/show.html.erb from 39 to 0, and found a codemod
  # blind spot worth writing down: a tag regex of `<tag[^>]*?>` truncates on a
  # literal `>` INSIDE an attribute value, and Stimulus actions contain one —
  # `data-action="change->nav-select#go"`. The `<select>` carrying it was
  # silently skipped, and only the repo-wide count disagreeing with the expected
  # drop revealed it. Five more elements repo-wide have an action arrow before a
  # `style=`; mask attribute VALUES, not just ERB, before scanning tags.
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
  # 858, NOT 745. The number ROSE on 2026-09-05 without a single inline style
  # being added, because the count was wrong: see STYLE_FORMS below. 745 was
  # never the number of inline styles in this repository, it was the number of
  # them written in one particular syntax.
  #
  # This is the ONE circumstance in which the ceiling may go up — a correction
  # to what is being counted, never a regression in what is being guarded. Any
  # later increase is a rot-back and must be rejected.
  let(:ceiling) { 790 }

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
  #
  # Masking ERB is NOT enough, and this guard missed a live defect on
  # 2026-09-05 because of it. A Stimulus action is plain markup containing a
  # literal `>`:
  #
  #     data-action="click->heatmap-chip#apply"
  #
  # `<[a-zA-Z][^>]*>` ends the "tag" at that arrow, so a second class= further
  # down the element is never seen. A summary chip on the SAP screen carried two
  # class attributes and this spec reported clean. TAG_SCAN steps over quoted
  # attribute values instead of stopping at the first `>`.
  TAG_SCAN = %r{<[a-zA-Z][^\s>]*(?:\s+(?:[^\s=>]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+))?)\s*)*/?>}m

  it "never leaves an element with two class attributes" do
    offenders = Dir.glob(view_root.join("**/*.erb")).flat_map do |path|
      masked = File.read(path).gsub(/<%.*?%>/m, "ERB")
      masked.scan(TAG_SCAN)
            .select { |tag| tag.scan(/(?:\A|\s)class\s*=/).size > 1 }
            .map { |tag| "#{path.sub(Rails.root.to_s + '/', '')}: #{tag.split.join(' ')[0, 110]}" }
    end

    expect(offenders).to be_empty, lambda {
      "#{offenders.size} element(s) carry two class attributes; the browser uses the " \
      "first and drops the second:\n  " + offenders.join("\n  ")
    }
  end

  # Every way an inline style reaches the browser, not just the one shape the
  # sweep happened to start with.
  #
  # This counted `style="..."` ONLY until 2026-09-05, and that hid 113 inline
  # styles from every measurement in the sweep — including 33 sitting in eight
  # files whose own commits said they were "at 0". Rails helpers take the style
  # as a keyword argument and it reaches the page as an attribute like any
  # other, so `style-src 'unsafe-inline'` is exactly as load-bearing for it:
  #
  #     <%= link_to "x", path, style: "font-size: 1.5rem;" %>
  #     # => <a href="..." style="font-size: 1.5rem;">x</a>
  #
  # A ratchet that cannot see a form of the thing it guards is not a weaker
  # ratchet, it is a false one: it reports zero and the directive still breaks
  # the page.
  STYLE_FORMS = [
    /style="[^"]*"/,      # <div style="...">
    /style='[^']*'/,      # <div style='...'>
    /style:\s*"[^"]*"/,   # link_to ..., style: "..."
    /style:\s*'[^']*'/    # link_to ..., style: '...'
  ].freeze

  # The SAME defect in the HELPER form, which the guard above cannot see.
  #
  # `link_to "x", path, class: "a", role: "button", class: "b"` is valid Ruby:
  # the last key wins and "a" is SILENTLY DROPPED. It is the exact failure the
  # two-class-attribute guard exists for, and this sweep produced one on
  # 2026-09-05 — a heat-map badge that would have lost `sparc-heatmap-badge`
  # and its status colour with nothing to report it. Ruby emits a warning at
  # compile time; nothing in the suite was reading it.
  it "never passes class: twice to the same helper call" do
    offenders = Dir.glob(view_root.join("**/*.erb")).flat_map do |path|
      rel = path.sub(Rails.root.to_s + "/", "")
      # An ERB expression tag, flattened, then scanned for two class: keys.
      File.read(path).scan(/<%=.*?%>/m).filter_map do |tag|
        # Only TOP-LEVEL keys count. `button_to ..., class: "a", form: { class: "b" }`
        # is correct and common: the second belongs to the generated <form>, not
        # the button. Strip balanced brace groups until none are left, so nested
        # hashes (and arrays of hashes, as `badges: [ { ... } ]`) drop out.
        flat = tag.dup
        flat = flat.sub(/\{[^{}]*\}/, "") while flat.match?(/\{[^{}]*\}/)
        next unless flat.scan(/(?:^|[\s,(])class:\s/).size > 1
        "#{rel}: #{tag.split.join(' ')[0, 120]}"
      end
    end

    expect(offenders).to be_empty, lambda {
      "#{offenders.size} helper call(s) pass class: twice; Ruby keeps the LAST " \
      "and drops the first silently:\n  " + offenders.join("\n  ")
    }
  end

  def inline_styles
    Dir.glob(view_root.join("**/*.erb")).flat_map do |path|
      src = File.read(path)
      STYLE_FORMS.flat_map { |re| src.scan(re).map { |m| [ path, m ] } }
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
