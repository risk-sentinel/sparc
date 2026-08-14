# frozen_string_literal: true

require "rails_helper"

# #870 — help must not cost the operator their work.
#
# Operators open help BECAUSE they are mid-task, so same-tab navigation turns a
# support aid into a context switch that discards a part-filled form. These
# specs pin the two halves: guides open in a new tab, and field-level help is
# present, keyboard-reachable, and free of inline handlers (CSP has no
# 'unsafe-inline').
RSpec.describe "Contextual help (#870)", type: :request do
  let(:user) { create(:user, admin: true) }
  let(:boundary) { create(:authorization_boundary) }

  before { sign_in_as(user) }

  # Rails renders target/rel in attribute order that varies; parse instead.
  def links_to(body, href_fragment)
    Nokogiri::HTML(body).css("a").select { |a| a["href"].to_s.include?(href_fragment) }
  end

  describe "guides open without leaving the current screen" do
    # #880 moved the navbar "?" to the in-page drawer, but deliberately left
    # the href/target as they were. That is not vestigial markup: it is the
    # fallback if help_drawer_controller never connects, and it keeps the
    # property this issue is actually about — the click cannot replace the
    # current page and discard a part-filled form.
    it "never navigates the navbar help control in place, even without JS" do
      get authorization_boundaries_path

      help = links_to(response.body, "/help").find { |a| a["class"].to_s.include?("sparc-nav-btn") }
      expect(help).to be_present, "expected the navbar ? control to be rendered"
      expect(help["target"]).to eq("_blank")
      expect(help["rel"]).to include("noopener")
      expect(help["rel"]).to include("noreferrer")
    end

    it "opens sidebar guide links in a new tab" do
      get authorization_boundaries_path

      guide_links = links_to(response.body, "/help/").select { |a| a["class"].to_s.include?("sparc-sidebar-leaf") }
      expect(guide_links).not_to be_empty

      guide_links.each do |a|
        expect(a["target"]).to eq("_blank"), "#{a['href']} should open in a new tab"
        expect(a["rel"].to_s).to include("noopener"), "#{a['href']} needs rel=noopener"
      end
    end

    # Before #880 this asserted the label said "opens in a new tab". It no
    # longer does, and must not: a screen-reader user has JS, so what they get
    # is the drawer. A label promising a new tab would now be describing the
    # fallback nobody with a working browser experiences. The dialog announces
    # itself — Bootstrap sets role=dialog + aria-modal on the offcanvas, which
    # carries its own accessible name (see the #880 spec).
    it "announces the navbar help control, and does not promise a new tab it no longer opens" do
      get authorization_boundaries_path

      help = links_to(response.body, "/help").find { |a| a["class"].to_s.include?("sparc-nav-btn") }
      expect(help["aria-label"].to_s).to match(/help/i)
      expect(help["aria-label"].to_s).not_to match(/new tab/i)
    end

    it "leaves the Help Center index navigating normally — it is a destination, not a reference" do
      get authorization_boundaries_path

      index = links_to(response.body, "/help").find do |a|
        a["class"].to_s.include?("sparc-sidebar-leaf") && a["href"].to_s.end_with?("/help")
      end
      expect(index).to be_present
      expect(index["target"]).to be_nil
    end

    it "still deep-links to the guide for the current screen" do
      get authorization_boundaries_path

      help = links_to(response.body, "/help").find { |a| a["class"].to_s.include?("sparc-nav-btn") }
      expect(help["href"]).to match(%r{/help})
    end
  end

  describe "field-level help" do
    it "renders a focusable control beside the labels it explains" do
      get new_authorization_boundary_path

      doc = Nokogiri::HTML(response.body)
      helps = doc.css("button.sparc-field-help")
      expect(helps.size).to be >= 3

      helps.each do |b|
        expect(b["type"]).to eq("button"), "must be type=button so it never submits the form"
        expect(b["data-bs-toggle"]).to eq("tooltip")
        expect(b["data-bs-title"].to_s).not_to be_empty
        expect(b["aria-label"].to_s).to start_with("Help:")
      end
    end

    it "is a button, not a span — hover-only help is unreachable by keyboard" do
      get new_authorization_boundary_path

      doc = Nokogiri::HTML(response.body)
      expect(doc.css("span.sparc-field-help")).to be_empty
      expect(doc.css("button.sparc-field-help")).not_to be_empty
    end

    it "carries no inline handlers — CSP has no 'unsafe-inline'" do
      get new_authorization_boundary_path

      doc = Nokogiri::HTML(response.body)
      doc.css("button.sparc-field-help").each do |b|
        inline = b.attributes.keys.grep(/\Aon/i)
        expect(inline).to be_empty, "inline handler(s) #{inline.inspect} would be blocked by CSP"
      end
    end

    it "appears on the membership form too" do
      get new_authorization_boundary_membership_path(boundary)

      expect(Nokogiri::HTML(response.body).css("button.sparc-field-help")).not_to be_empty
    end

    it "renders nothing when there is no help text to give" do
      expect(helper_field_help(nil)).to be_nil
      expect(helper_field_help("")).to be_nil
    end

    # Exercise the helper directly for the blank cases.
    def helper_field_help(text)
      ApplicationController.helpers.field_help(text)
    end
  end
end
