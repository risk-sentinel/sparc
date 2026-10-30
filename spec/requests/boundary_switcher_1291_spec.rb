# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1291 — the boundary switcher in the shell header. What it lists
# (only reachable boundaries, grouped by organization, recently used first),
# where each choice leads, and that its "recently used" cookie can never name a
# boundary the viewer cannot reach.
RSpec.describe "Boundary switcher (1.18.0-rf #1291)", type: :request do
  let(:agency) { create(:organization, name: "Agency") }
  let(:bureau) { create(:organization, name: "Bureau") }
  let!(:alpha) { create(:authorization_boundary, name: "Alpha ATO", organization: agency) }
  let!(:bravo) { create(:authorization_boundary, name: "Bravo ATO", organization: bureau) }
  let!(:loose) { create(:authorization_boundary, name: "Loose ATO", organization: nil) }
  let!(:hidden) { create(:authorization_boundary, name: "Hidden ATO", organization: agency) }
  let(:member) do
    create(:user).tap do |u|
      [ alpha, bravo, loose ].each do |b|
        %w[authorization_boundaries.read poam.read].each { grant_permission(u, _1, authorization_boundary: b) }
      end
    end
  end

  def page = Nokogiri::HTML(response.body)

  def panel = page.at_css("[data-testid=shell-switcher-panel]")

  def groups = panel.css("[data-testid=shell-switcher-group]").map(&:text)

  def entries = panel.css("[data-testid=shell-switcher-item]").map { [ _1["data-group"], _1.at_css(".sparc-switcher__name").text ] }

  def link_for(boundary, group: nil)
    panel.css("[data-testid=shell-switcher-item][data-boundary-id='#{boundary.id}']")
         .find { group.nil? || _1["data-group"] == group }["href"]
  end

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true)
    sign_in_as(member)
  end

  it "lists only reachable boundaries, by organization, with no organization last" do
    get "/"

    expect(groups).to eq([ "Agency", "Bureau", "No organization" ])
    expect(entries.map(&:last)).to eq([ "Alpha ATO", "Bravo ATO", "Loose ATO" ])
    expect(response.body).not_to include("Hidden ATO")
  end

  it "keeps a filtered list's screen and its other filters, and drops the page" do
    get "/poam_documents", params: { authorization_boundary_id: alpha.id, q: "x", page: 2 }

    query = Rack::Utils.parse_query(URI(link_for(bravo)).query)
    expect(URI(link_for(bravo)).path).to eq("/poam_documents")
    expect(query).to eq("authorization_boundary_id" => bravo.id.to_s, "q" => "x")
    all = panel.at_css("[data-testid=shell-switcher-all]")["href"]
    expect(Rack::Utils.parse_query(URI(all).query)).to eq("q" => "x")
  end

  it "opens the boundary's page from anywhere else" do
    get "/authorization_boundaries/#{alpha.to_param}"
    expect(link_for(bravo)).to eq("/authorization_boundaries/#{bravo.to_param}")
    expect(panel.at_css("[data-testid=shell-switcher-all]")["href"]).to eq("/authorization_boundaries")
    expect(panel.at_css("[aria-current=true]")["data-boundary-id"]).to eq(alpha.id.to_s)
  end

  it "lists recently used boundaries first, most recent first" do
    get "/authorization_boundaries/#{alpha.to_param}"
    get "/poam_documents", params: { authorization_boundary_id: loose.id }
    get "/"

    expect(groups.first).to eq("Recently used")
    expect(entries.select { _1.first == "recent" }.map(&:last)).to eq([ "Loose ATO", "Alpha ATO" ])
  end

  it "drops a recent boundary the viewer has since lost access to" do
    grant_permission(member, "authorization_boundaries.read", authorization_boundary: hidden)
    get "/authorization_boundaries/#{bravo.to_param}"
    get "/authorization_boundaries/#{hidden.to_param}"
    UserRole.where(user: member, authorization_boundary: hidden).destroy_all
    get "/"

    expect(entries.select { _1.first == "recent" }.map(&:last)).to eq([ "Bravo ATO" ])
    expect(response.body).not_to include("Hidden ATO")
  end

  it "ignores another viewer's recent boundaries" do
    get "/authorization_boundaries/#{alpha.to_param}"
    other = create(:user).tap { |u| grant_permission(u, "authorization_boundaries.read", authorization_boundary: alpha) }
    sign_in_as(other)
    get "/"

    expect(groups).not_to include("Recently used")
  end

  it "is not rendered with SPARC_NAV_SHELL off" do
    allow(SparcConfig).to receive(:nav_shell?).and_return(false)
    get "/"

    expect(panel).to be_nil
  end
end
