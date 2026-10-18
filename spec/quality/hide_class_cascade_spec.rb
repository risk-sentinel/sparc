# frozen_string_literal: true

require "rails_helper"

# #1107 — `.sparc-d-none` must win the cascade over every class that sets
# `display`, or `setVisible(el, false)` silently leaves `el` on screen.
#
# PR #1110 made it `display: none !important`. That ends the source-order race
# with our own component classes, which do not use !important, and ties with
# Bootstrap's display utilities (`.d-flex` is `display: flex !important`). A tie
# between two !important single-class rules is decided by order again, so the
# win holds only while all three of these stay true. Each one is a way the
# cascade can rot back without any page visibly changing until an element
# carries both classes.
RSpec.describe "The hide class wins the cascade (#1107)" do
  def stylesheets
    %w[application.css sparc-theme.css].index_with do |name|
      Rails.root.join("app/assets/stylesheets", name).read.gsub(%r{/\*.*?\*/}m, "")
    end
  end

  it "declares .sparc-d-none as display: none !important" do
    rule = stylesheets["sparc-theme.css"][/^\.sparc-d-none\s*\{([^}]*)\}/, 1]

    expect(rule).to match(/display\s*:\s*none\s*!important/)
  end

  # A later `display: flex !important` in our own CSS would tie on importance
  # and win on order: the exact #1107 defect, one keyword further down.
  it "has no other rule that sets a visible display with !important" do
    offenders = stylesheets.flat_map do |name, css|
      css.scan(/display\s*:\s*([^;}]*?)\s*!important/).flatten
         .reject { |value| value.strip == "none" }
         .map { |value| "#{name}: display: #{value} !important" }
    end

    expect(offenders).to be_empty
  end

  # Bootstrap's display utilities carry !important too. Our sheet has to load
  # AFTER Bootstrap's for the tie to go our way.
  it "loads sparc-theme after Bootstrap in every layout that loads both" do
    # The tag, not the bare name: the layout's theme script also reads a
    # localStorage key called "sparc-theme", earlier in the head.
    theme_tag = /stylesheet_link_tag\s+"sparc-theme"/
    bootstrap = %r{<link[^>]+bootstrap(?:\.min)?\.css}
    layouts = Rails.root.glob("app/views/layouts/*.erb").select do |path|
      path.read.match?(theme_tag) && path.read.match?(bootstrap)
    end

    expect(layouts.map { |p| p.basename.to_s }).to include("application.html.erb", "login.html.erb")
    layouts.each do |path|
      html = path.read
      expect(html =~ theme_tag).to be > (html =~ bootstrap),
                                   "#{path.basename} loads sparc-theme before Bootstrap"
    end
  end
end
