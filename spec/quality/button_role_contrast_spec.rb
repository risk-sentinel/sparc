# frozen_string_literal: true

require "rails_helper"

# #950 — the nine button roles must pass WCAG 2.1 AA (4.5:1) in BOTH themes.
#
# Owner rule 3 is "a11y / WCAG compliant, verified by measurement, not by eye",
# and rule 4 is "dark mode carries NO fill — outline and text only". Rule 4 is
# what makes this spec necessary rather than nice to have: with no fill, the
# label colour IS the contrast, so a token nudge that looks harmless silently
# drops a role below AA with nothing to catch it.
#
# Three of the nine failed on the raw tokens when the roles were first written —
# edit 4.39 light, destroy 3.98 dark, wizard 4.10 dark. None was visible by eye;
# all three came out of this arithmetic. This spec is that arithmetic, kept.
#
# It reads the stylesheet and resolves var() indirection back to the token
# blocks, rather than asserting against a copied table, so it fails when the CSS
# drifts instead of when someone forgets to update a fixture.
#
# No top-level constants: a constant assigned inside a describe block lands on
# Object and is visible to every other spec file (#1035, and
# spec/quality/spec_constant_isolation_spec.rb enforces it). `ROLES` and
# `SURFACES` are exactly the names another file would also pick.
RSpec.describe "Button role contrast (#950)" do
  def css
    @css ||= Rails.root.join("app/assets/stylesheets/sparc-theme.css").read
  end

  def roles
    %w[create update import export view edit wizard cancel destroy]
  end

  # Roles that carry a fill in LIGHT (they commit something). Rule 4 strips
  # every one of them back to outline in dark.
  def filled_in_light
    %w[create update import destroy]
  end

  def surfaces(theme)
    theme == :dark ? { "body" => "#1e2632", "card" => "#252d3a" }
                   : { "body" => "#f5f5f5", "card" => "#ffffff" }
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

  def tokens_for(theme)
    block =
      if theme == :dark
        css[/\[data-bs-theme="dark"\]\s*\{(.*?)\n\}/m, 1]
      else
        css[/^:root\s*,?[^{]*\{(.*?)\n\}/m, 1]
      end
    raise "could not find the #{theme} token block in sparc-theme.css" if block.nil?

    block.scan(/(--sparc-[a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{3,8})/).to_h
  end

  def role_colour(role, theme)
    dark_override = css[
      /\[data-bs-theme="dark"\]\s+\.sparc-action--#{role}\s*\{[^}]*--sparc-action-fg:\s*([^;]+);/, 1
    ]
    declaration =
      if theme == :dark && dark_override
        dark_override.strip
      else
        css[/^\.sparc-action--#{role}\s*\{[^}]*--sparc-action-fg:\s*([^;]+);/, 1]&.strip
      end
    raise "no --sparc-action-fg declared for role #{role}" if declaration.nil?

    if (var = declaration.match(/var\(\s*(--sparc-[a-z0-9-]+)\s*\)/))
      tokens_for(theme).fetch(var[1]) { raise "token #{var[1]} is not defined for #{theme}" }
    else
      declaration[/#[0-9a-fA-F]{3,8}/] or
        raise "role #{role} (#{theme}) is neither a var() nor a hex literal: #{declaration}"
    end
  end

  it "defines each of the nine roles exactly once" do
    duplicated = roles.reject { |role| css.scan(/^\.sparc-action--#{role}\s*\{[^}]*--sparc-action-fg:/).length == 1 }
    expect(duplicated).to be_empty,
      "rule 5 is that a function is defined in ONE place; these are not: #{duplicated.join(', ')}"
  end

  it "passes AA 4.5:1 on every light surface, for every role" do
    failures = roles.flat_map do |role|
      fg = role_colour(role, :light)
      surfaces(:light).filter_map do |name, bg|
        # A filled light role puts WHITE on the fill; an outline role puts the
        # role colour on the surface.
        ratio = filled_in_light.include?(role) ? contrast("#ffffff", fg) : contrast(fg, bg)
        "#{role} on #{name} (#{fg}) = #{ratio}:1" if ratio < 4.5
      end
    end
    expect(failures).to be_empty, "WCAG AA failures in light:\n  #{failures.join("\n  ")}"
  end

  it "passes AA 4.5:1 on every dark surface, where rule 4 leaves only the label" do
    failures = roles.flat_map do |role|
      fg = role_colour(role, :dark)
      surfaces(:dark).filter_map do |name, bg|
        ratio = contrast(fg, bg)
        "#{role} on #{name} (#{fg}) = #{ratio}:1" if ratio < 4.5
      end
    end
    expect(failures).to be_empty,
      "WCAG AA failures in dark — dark carries no fill, so this colour IS the " \
      "contrast:\n  #{failures.join("\n  ")}"
  end

  it "strips the fill from every light-filled role in dark mode (rule 4)" do
    missing = filled_in_light.reject do |role|
      css.match?(/\[data-bs-theme="dark"\][^{]*\.sparc-action--#{role}[^{]*\{/)
    end
    expect(missing).to be_empty,
      "these roles are filled in light but have no dark override, so rule 4 " \
      "would leave them filled: #{missing.join(', ')}"

    dark_rule = css[/\[data-bs-theme="dark"\][^{]*\.sparc-action--destroy\s*\{([^}]*)\}/m, 1]
    expect(dark_rule).to include("background: transparent"),
      "the dark override must actually set a transparent background"
  end
end
