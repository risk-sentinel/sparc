# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1288 — the OSCAL layer colours clear WCAG 2.1 AA in both themes,
# on every surface they land on.
#
# They used to be four hard-coded hexes chosen for the dark navbar. On the light
# dropdown menus, where the same values coloured each layer's heading, they
# measured 1.91-3.10:1: every layer heading failed, and nothing measured it.
#
# Now they are tokens (--sparc-layer-*), and this spec reads them out of
# sparc-theme.css, so nudging one below AA fails here rather than in a screen
# reader's hands. It measures each token:
#   * as text (4.5:1) on the page, card and card-alt surfaces of its theme;
#   * as text on its own 14% tint (how counters use it);
#   * the -on-navy variants on the navbar (#212529), which is dark in BOTH
#     themes (#974), as text and as an indicator.
# No top-level constants (spec_constant_isolation_spec.rb).
RSpec.describe "Layer colour contrast (#1288)" do
  def css
    @css ||= Rails.root.join("app/assets/stylesheets/sparc-theme.css").read
  end

  def layers = %w[controls implementation assessment enterprise]

  # The first `:root` block holds the light tokens; the first
  # `[data-bs-theme="dark"] {` block the dark ones.
  def block(selector)
    start = css.index(selector) or raise "no #{selector} block in sparc-theme.css"
    css[start..css.index("\n}", start)]
  end

  def token(block_text, name)
    block_text[/--#{Regexp.escape(name)}:\s*(#\h{6})/, 1] or raise "--#{name} not found"
  end

  def surfaces
    {
      light: { "page" => "#f5f5f5", "card" => "#ffffff", "card-alt" => "#f8f9fa" },
      dark: { "page" => "#0f1419", "card" => "#1e2632", "card-alt" => "#252d3a" }
    }
  end

  def navbar = "#212529"

  def relative_luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map { |c| c.to_i(16) / 255.0 }
    lin = channels.map { |c| c <= 0.04045 ? c / 12.92 : (((c + 0.055) / 1.055)**2.4) }
    (0.2126 * lin[0]) + (0.7152 * lin[1]) + (0.0722 * lin[2])
  end

  def contrast(fore, back)
    hi, lo = [ relative_luminance(fore), relative_luminance(back) ].minmax.reverse
    ((hi + 0.05) / (lo + 0.05)).round(2)
  end

  # `color-mix(in srgb, <c> <pct>%, <bg>)`
  def tint(hex, pct, bg)
    fg = hex.delete_prefix("#").scan(/../).map { |c| c.to_i(16) }
    back = bg.delete_prefix("#").scan(/../).map { |c| c.to_i(16) }
    "#%02x%02x%02x" % fg.zip(back).map { |f, b| ((f * pct) + (b * (1 - pct))).round }
  end

  { light: ":root,", dark: "[data-bs-theme=\"dark\"] {" }.each do |theme, selector|
    describe "#{theme} theme" do
      it "reads every layer at 4.5:1 as text on the page, card and card-alt" do
        failures = layers.flat_map do |layer|
          value = token(block(selector), "sparc-layer-#{layer}")
          surfaces.fetch(theme).filter_map do |surface, bg|
            ratio = contrast(value, bg)
            "#{layer} #{value} on #{surface} #{bg}: #{ratio}" if ratio < 4.5
          end
        end
        expect(failures).to be_empty, "below WCAG AA 4.5:1:\n#{failures.join("\n")}"
      end

      it "reads every layer at 4.5:1 on its own 14% tint (counters)" do
        card = surfaces.fetch(theme).fetch("card")
        failures = layers.filter_map do |layer|
          value = token(block(selector), "sparc-layer-#{layer}")
          ratio = contrast(value, tint(value, 0.14, card))
          "#{layer} #{value} on its tint: #{ratio}" if ratio < 4.5
        end
        expect(failures).to be_empty, failures.join("\n")
      end
    end
  end

  it "reads every -on-navy layer at 4.5:1 on the navbar, in both themes" do
    failures = layers.filter_map do |layer|
      value = token(block(":root,"), "sparc-layer-#{layer}-on-navy")
      ratio = contrast(value, navbar)
      "#{layer}-on-navy #{value}: #{ratio}" if ratio < 4.5
    end
    expect(failures).to be_empty, failures.join("\n")
  end

  it "leaves no hard-coded layer colour in the stylesheet's rules or the navigation" do
    retired = %w[#6ba3d6 #6abf69 #e8a838 #d4943c #bb6bd9]
    rules = css.gsub(%r{/\*.*?\*/}m, "").lines.reject { |l| l.include?("--sparc-") }
    views = Dir[Rails.root.join("app/views/shared/{_main_nav,_controls_nav,_sidebar,_sidebar_boundary}.html.erb")]
              .map { |f| File.read(f) }.join

    leftovers = retired.select { |hex| rules.join.downcase.include?(hex) || views.downcase.include?(hex) }
    expect(leftovers).to be_empty, "hard-coded layer hexes remain: #{leftovers.join(', ')}"
  end
end
