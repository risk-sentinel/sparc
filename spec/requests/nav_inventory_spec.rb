# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf phase 0 (#1286, #1297, #1307) — the navigation each viewer is
# offered, checked against the inventory recorded before the refactor.
#
# Both directions, because either alone permits a regression:
#   * every recorded entry is still offered — a link users had is not lost;
#   * every offered entry is recorded — a link is never added (or shown to a
#     viewer who cannot use it) without someone changing the inventory on
#     purpose, in a reviewed diff.
#
# Regenerate after a DELIBERATE navigation change:
#   NAV_INVENTORY_WRITE=1 bundle exec rspec spec/requests/nav_inventory_spec.rb
# and review the JSON diff: a removed entry is a link users lose.
#
# The header's reachability rules themselves (#974) are pinned by
# header_nav_parity_974_spec.rb; boundary visibility by
# boundary_visibility_1245_spec.rb. This spec is the inventory over both.
#
# NIST 800-53: AC-3, AC-6 (a viewer is offered only what they may open).
RSpec.describe "Navigation inventory (1.18.0-rf phase 0)", type: :request do
  let(:org) { create(:organization, name: "Example Agency") }
  let!(:mine) { create(:authorization_boundary, name: "Mine System", organization: org, status: "active") }
  let!(:theirs) { create(:authorization_boundary, name: "Theirs System", organization: org) }

  let(:member) do
    create(:user).tap do |u|
      create(:organization_membership, user: u, organization: org)
      grant_permission(u, "authorization_boundaries.read", authorization_boundary: mine)
    end
  end
  let(:admin) { create(:user, :admin) }

  def navigation_for(posture)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(posture[:auth])
    allow(SparcConfig).to receive(:enable_local_login?).and_return(posture[:auth])
    allow(SparcConfig).to receive(:public_catalogs?).and_return(posture[:public])
    allow(SparcConfig).to receive(:fido2_enabled?).and_return(true)
    sign_in_as(public_send(posture[:user])) if posture[:user]

    posture[:pages].flat_map do |page|
      get public_send(NavInventory::PAGE_PATHS.fetch(page))
      expect(response).to have_http_status(:ok), "#{page} returned #{response.status}"
      NavInventory.extract(response.body)
    end.uniq.sort_by { |e| [ e["menu"], e["label"], e["path"] ] }
  end

  def describe_entries(entries)
    entries.map { |e| "  #{e['menu']} | #{e['label']} | #{e['path']}" }.join("\n")
  end

  if ENV["NAV_INVENTORY_WRITE"] == "1"
    it "writes the inventory" do
      recorded = NavInventory::POSTURES.to_h { |name, posture| [ name, navigation_for(posture) ] }
      NavInventory.write(recorded)
    end
  end

  NavInventory::POSTURES.each do |name, posture|
    it "offers the #{name} viewer exactly the recorded navigation" do
      recorded = NavInventory.load.fetch("postures").fetch(name)
      offered = navigation_for(posture)

      lost = recorded - offered
      added = offered - recorded
      expect(lost).to be_empty,
        "#{name}: links in the inventory are no longer offered:\n#{describe_entries(lost)}"
      expect(added).to be_empty,
        "#{name}: links offered but not in the inventory (record them on purpose):\n#{describe_entries(added)}"
    end
  end

  it "records each guide once, not once per wiki page" do
    member_nav = NavInventory.load.fetch("postures").fetch("signed_in_member")
    guides = member_nav.select { |e| e["label"] == NavInventory::GUIDE_LABEL }
    expect(guides.size).to eq(1)
  end

  it "never offers a signed-out viewer the boundary documents or the account menu" do
    nav = NavInventory.load.fetch("postures").fetch("signed_out")
    paths = nav.map { |e| e["path"] }
    expect(paths).not_to include("/ssp_documents", "/poam_documents", "/admin/users")
    expect(nav.map { |e| e["menu"] }).not_to include("Account")
  end

  it "never offers the member an administrator screen" do
    nav = NavInventory.load.fetch("postures").fetch("signed_in_member")
    expect(nav.map { |e| e["path"] }.grep(%r{\A/admin/})).to be_empty
  end
end
