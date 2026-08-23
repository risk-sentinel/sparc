# frozen_string_literal: true

require "rails_helper"

# #950 — every button intent must clear WCAG 2.1 AA (4.5:1) in both themes,
# against the surface its label actually lands on.
#
# THE SURFACE IS THE POINT. Light mode draws every role as a 20% tint of its own
# intent (12% for ghost), so the label sits on a pale version of ITSELF — a much
# tighter pair than the same colour on the page. `primary` measures 5.42:1 on
# #f5f5f5 but only 4.09:1 on its own tint. Six of the seven intents failed that
# way when the schema was first written, and none of it was visible by eye:
#
#     primary 4.09 · positive 4.35 · info 4.40 · accent 4.39
#     caution 4.13 · danger 4.00          (neutral 6.79, the only pass)
#
# The fix was to split the token: the tint and border keep the approved value,
# and a separate `-ink` token carries the label a few points darker. This spec
# is what keeps those two in step — nudge a tint and the ink stops passing.
#
# It reads sparc-theme.css and resolves var() indirection back to the token
# blocks, so it fails when the stylesheet drifts rather than when someone
# forgets to update a fixture. No top-level constants: a constant assigned in a
# describe block lands on Object and leaks to every other spec file (#1035, and
# spec/quality/spec_constant_isolation_spec.rb enforces it).
RSpec.describe "Button role contrast (#950)" do
  def css
    @css ||= Rails.root.join("app/assets/stylesheets/sparc-theme.css").read
  end

  def intents
    %w[neutral primary positive info caution danger accent]
  end

  # Light tints the label's own colour behind it; dark has no fill at all, so
  # the label sits on the page/card surface.
  def light_tints
    { "solid/outline (20%)" => 0.20, "ghost (12%)" => 0.12 }
  end

  def dark_surfaces
    { "body" => "#1e2632", "card" => "#252d3a" }
  end

  def relative_luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    lin = channels.map { |c| c <= 0.04045 ? c / 12.92 : (((c + 0.055) / 1.055)**2.4) }
    (0.2126 * lin[0]) + (0.7152 * lin[1]) + (0.0722 * lin[2])
  end

  def contrast(fore, back)
    hi, lo = [ relative_luminance(fore), relative_luminance(back) ].minmax.reverse
    ((hi + 0.05) / (lo + 0.05)).round(2)
  end

  # `color-mix(in srgb, <c> <pct>%, #fff)` — what the browser will actually paint.
  def tint(hex, pct)
    rgb = hex.delete_prefix("#").scan(/../).map { |c| c.to_i(16) }
    "#%02x%02x%02x" % rgb.map { |v| ((v * pct) + (255 * (1 - pct))).round }
  end

  # sparc-theme.css already contained a `:root, [data-bs-theme="light"]` block
  # and a `[data-bs-theme="dark"]` block long before #950, so matching on the
  # selector alone finds the WRONG one — the original theme tokens, which carry
  # no `--sparc-i-*` at all. Select the block by what it CONTAINS instead.
  # Comments must be stripped BEFORE scanning. The #950 block's own comment
  # contains the literal text `[data-bs-theme="dark"]`, which matched as a
  # selector and captured the *light* block that follows it — so every dark
  # token silently resolved to its light value and the dark assertions failed
  # with light hexes. A comment that mentions a selector is not a rule.
  def stripped_css
    @stripped_css ||= css.gsub(%r{/\*.*?\*/}m, "")
  end

  def token_block(theme)
    selector = theme == :dark ? '[data-bs-theme="dark"]' : '[data-bs-theme="light"]'
    blocks = stripped_css.scan(/(?:^|\n)([^{}\n]*#{Regexp.escape(selector)}[^{}]*)\{([^{}]*)\}/m)
    hit = blocks.find { |_sel, body| body.include?("--sparc-i-neutral") }
    hit or raise "could not find the #{theme} intent token block (no block carrying --sparc-i-*)"
    hit[1]
  end

  def token(theme, name)
    block = token_block(theme)
    block[/--sparc-i-#{name}\s*:\s*(#[0-9a-fA-F]{3,8})/, 1] or
      raise "--sparc-i-#{name} is not defined for #{theme}"
  end

  it "defines a tint token and an ink token for all seven intents, in both themes" do
    missing = []
    %i[light dark].each do |theme|
      intents.each do |name|
        missing << "#{theme}/--sparc-i-#{name}" unless token_block(theme).match?(/--sparc-i-#{name}\s*:/)
        missing << "#{theme}/--sparc-i-#{name}-ink" unless token_block(theme).match?(/--sparc-i-#{name}-ink\s*:/)
      end
    end
    expect(missing).to be_empty, "undefined intent tokens: #{missing.join(', ')}"
  end

  it "passes AA 4.5:1 in light, where the label sits on a tint of itself" do
    failures = intents.flat_map do |name|
      ink = token(:light, "#{name}-ink")
      fill = token(:light, name)
      light_tints.filter_map do |label, pct|
        ratio = contrast(ink, tint(fill, pct))
        "#{name} #{label}: ink #{ink} on #{tint(fill, pct)} = #{ratio}:1" if ratio < 4.5
      end
    end
    expect(failures).to be_empty,
      "WCAG AA failures in light — the label is on a tint of its own intent, " \
      "which is a far tighter pair than the same colour on the page:\n  #{failures.join("\n  ")}"
  end

  it "passes AA 4.5:1 in dark, where there is no fill and the label is the contrast" do
    failures = intents.flat_map do |name|
      ink = token(:dark, "#{name}-ink")
      dark_surfaces.filter_map do |label, bg|
        ratio = contrast(ink, bg)
        "#{name} on #{label} (#{ink}) = #{ratio}:1" if ratio < 4.5
      end
    end
    expect(failures).to be_empty, "WCAG AA failures in dark:\n  #{failures.join("\n  ")}"
  end

  it "carries no fill at all in dark mode" do
    dark_rule = css[/\[data-bs-theme="dark"\]\s+\.sparc-action--solid,\s*\n\[data-bs-theme="dark"\]\s+\.sparc-action--outline\s*\{([^}]*)\}/m, 1]
    expect(dark_rule).to include("background: transparent"),
      "dark mode must carry no fill — solid and outline are drawn identically"

    ghost = css[/\[data-bs-theme="dark"\]\s+\.sparc-action--ghost\s*\{([^}]*)\}/m, 1]
    expect(ghost).to include("background: transparent"), "ghost must not be filled in dark either"
    expect(ghost).to match(/border-color:\s*color-mix/),
      "ghost needs a visible edge in dark or it is indistinguishable from body text"
  end

  it "keeps light emphasis on the border, never on an opaque fill" do
    %w[solid outline ghost].each do |emphasis|
      rule = css[/^\.sparc-action--#{emphasis}\s*\{([^}]*)\}/m, 1]
      expect(rule).to be_present, "no light rule for .sparc-action--#{emphasis}"
      expect(rule).to match(/background:\s*color-mix/),
        ".sparc-action--#{emphasis} must be a tint, not an opaque fill — mixing " \
        "opaque and translucent in one theme is the defect this system exists to remove"
    end
  end
end
