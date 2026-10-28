# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1289 — SVG icons drawn from the Lucide sprite, in place of emoji.
RSpec.describe IconHelper, type: :helper do
  let(:svg) { Nokogiri::HTML.fragment(helper.icon(name, **opts)).at_css("svg") }
  let(:name) { "house" }
  let(:opts) { {} }

  it "draws the named symbol from the sprite" do
    expect(svg.at_css("use")["href"]).to eq("#i-house")
    expect(svg["class"]).to eq("sparc-icon")
  end

  it "is hidden from screen readers when it only decorates" do
    expect(svg["aria-hidden"]).to eq("true")
    expect(svg["role"]).to be_nil
    expect(svg["focusable"]).to eq("false")
  end

  context "with a label" do
    let(:opts) { { label: "Home" } }

    it "is announced as an image with that name" do
      expect(svg["role"]).to eq("img")
      expect(svg["aria-label"]).to eq("Home")
      expect(svg["aria-hidden"]).to be_nil
    end
  end

  context "with an extra class" do
    let(:opts) { { css_class: "sparc-icon-sm" } }

    it "keeps the base class" do
      expect(svg["class"]).to eq("sparc-icon sparc-icon-sm")
    end
  end

  it "refuses a name the sprite does not hold" do
    expect { helper.icon("no-such-icon") }.to raise_error(ArgumentError, /unknown icon "no-such-icon"/)
  end

  # A view that names a missing icon raises at render time; this catches it
  # without rendering every view.
  it "holds every icon a view names" do
    used = Dir[Rails.root.join("app/views/**/*.erb")].flat_map { |f| File.read(f).scan(/\bicon\("([a-z0-9-]+)"/).flatten }.uniq
    expect(used).not_to be_empty
    expect(used - IconHelper.names).to be_empty
  end
end
