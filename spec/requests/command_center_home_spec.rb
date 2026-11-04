# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf — the command-center home (owner, 2026-10-31, concept A): a strip
# of the four layers' counts, layer cards with one row per screen, and a rail
# with quick actions and each boundary's activity. What each viewer is offered
# is checked in both directions: a quick action shows exactly when the Create
# menu would offer it.
RSpec.describe "Command-center home (1.18.0-rf)", type: :request do
  let(:alpha) { create(:authorization_boundary, name: "Alpha ATO") }

  def page = Nokogiri::HTML(response.body)

  def quick_actions = page.css("[data-testid=org-quick-action]").to_h { [ _1["data-item"], _1["href"] ] }

  before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true) }

  describe "the inventory strip" do
    it "is one card per layer, each headed in main's heading colour, holding every tile" do
      sign_in_as(create(:user, :admin))
      get root_path

      strip = page.at_css("[data-home-inventory]")
      cards = strip.css(".sparc-home-strip__card")
      expect(cards.map { _1.at_css("h2").text.squish }).to eq(%w[Controls Implementation Assessment Enterprise])
      expect(cards.map { _1.at_css("h2")["class"][/sparc-heading-\w+/] })
        .to eq(%w[sparc-heading-controls sparc-heading-implementation sparc-heading-assessment sparc-heading-enterprise])
      expect(cards.map { _1["class"][/sparc-accent--\w+/] })
        .to eq(%w[sparc-accent--blue sparc-accent--green sparc-accent--carrot sparc-accent--purple])
      # #1339 — 14 less the Families and Controls tiles.
      expect(strip.css("a[data-home-tile]").size).to eq(12)
    end
  end

  describe "the layer cards" do
    it "head each layer with main's layer bar" do
      sign_in_as(create(:user, :admin))
      get root_path

      page.css("[data-testid=org-lane]").each do |lane|
        expect(lane.at_css(".sparc-home-layer__title > .sparc-group-bar")).to be_present, lane["data-layer"]
      end
    end
  end

  describe "Start something" do
    it "offers an administrator the four quick actions, each the Create menu's own link" do
      sign_in_as(create(:user, :admin))
      get root_path
      create_menu = page.css("[data-testid=shell-create-item]").to_h { [ _1["data-item"], _1["href"] ] }

      expect(quick_actions.keys).to eq(%w[ssp_documents evidences authorization_boundaries cdef_documents])
      expect(quick_actions).to eq(create_menu.slice(*quick_actions.keys))
    end

    it "offers a member only what they may create" do
      member = create(:user)
      grant_permission(member, "authorization_boundaries.read", authorization_boundary: alpha)
      grant_permission(member, "ssp.write", authorization_boundary: alpha)
      sign_in_as(member)
      get root_path

      expect(quick_actions).to eq("ssp_documents" => new_ssp_document_path)
    end

    it "is not shown to someone who may create nothing" do
      member = create(:user)
      grant_permission(member, "authorization_boundaries.read", authorization_boundary: alpha)
      sign_in_as(member)
      get root_path

      expect(page.at_css("[data-testid=org-quick-actions]")).to be_nil
    end
  end

  describe "the boundaries in the rail" do
    it "draws each boundary's activity from the audit log" do
      ssp = create(:ssp_document, authorization_boundary: alpha)
      quiet = create(:authorization_boundary, name: "Quiet ATO")
      2.times { AuditEvent.create!(action: "ssp_document_created", subject_type: "SspDocument", subject_id: ssp.id) }
      sign_in_as(create(:user, :admin))
      get root_path

      rows = page.css("[data-testid=org-recent-boundaries] li")
      total = ->(b) { rows.find { _1.text.include?(b.name) }.at_css("[data-testid=boundary-sparkline]")["data-total"] }
      expect(total.(alpha)).to eq("2")
      expect(total.(quiet)).to eq("0")
    end
  end
end
