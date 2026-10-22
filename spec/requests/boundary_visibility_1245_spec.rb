# frozen_string_literal: true

require "rails_helper"

# #1245, #1247, #1250 — what a user is shown about authorization boundaries is
# what they have permission to see (owner, 2026-10-22), from ONE definition:
# AuthorizationBoundary.visible_to, which answers exactly what the show page's
# read guard answers (#1244).
#
# Before this:
#   * the sidebar listed every boundary in the user's organizations;
#   * the boundary list and its tiles covered the whole instance;
#   * the Enterprise menu offered administrator screens to everyone;
#   * the list showed Edit, Delete and New to anyone, coloured one status three
#     ways, and counted legacy membership rows as "Members";
#   * the Completeness checklist ignored role-assigned personnel, showed raw
#     role keys, sent the POA&M tile to every boundary's POA&Ms, and counted an
#     optional absence as red.
#
# NIST 800-53: AC-3, AC-4 (no cross-boundary disclosure), AC-6.
RSpec.describe "Boundary visibility and the boundary list (#1245 #1247 #1250)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:org)     { create(:organization, name: "Example Agency") }
  let!(:mine)   { create(:authorization_boundary, name: "Mine System", organization: org, status: "active") }
  let!(:theirs) { create(:authorization_boundary, name: "Theirs System", organization: org) }
  let(:user)    { create(:user).tap { |u| create(:organization_membership, user: u, organization: org) } }

  def grant_read_on(boundary) = grant_permission(user, "authorization_boundaries.read", authorization_boundary: boundary)

  describe "AuthorizationBoundary.visible_to" do
    it "is every boundary for an administrator" do
      expect(AuthorizationBoundary.visible_to(create(:user, :admin))).to include(mine, theirs)
    end

    it "is every boundary for an instance-level read grant (Global Viewer)" do
      grant_permission(user, "authorization_boundaries.read")
      expect(AuthorizationBoundary.visible_to(user)).to include(mine, theirs)
    end

    it "is only the boundaries a role grants read on" do
      grant_read_on(mine)
      expect(AuthorizationBoundary.visible_to(user)).to contain_exactly(mine)
    end

    it "is nothing without a grant, and everything with auth disabled" do
      expect(AuthorizationBoundary.visible_to(user)).to be_empty
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
      expect(AuthorizationBoundary.visible_to(nil)).to include(mine, theirs)
    end
  end

  describe "the sidebar and the Enterprise menu" do
    before do
      grant_read_on(mine)
      sign_in_as(user)
      get root_path
    end

    let(:page) { Nokogiri::HTML(response.body) }

    it "lists only the user's boundary in the sidebar" do
      sidebar = page.at_css("#sidebarOrg#{org.id}")
      expect(sidebar.text).to include("Mine System")
      expect(sidebar.text).not_to include("Theirs System")
    end

    it "lists only the user's boundary in the Enterprise menu" do
      menu = page.css(".sparc-nav-boundaries + .dropdown-menu").text
      expect(menu).to include("Mine System")
      expect(menu).not_to include("Theirs System")
    end

    # Both are administrator screens. (The homepage's Organizations card is
    # #1243's, which rebuilds those cards.)
    it "offers a non-administrator neither Organizations nor Federation Peers in the Enterprise menu" do
      menu = page.css(".sparc-nav-boundaries + .dropdown-menu").to_html
      expect(menu).to include(authorization_boundaries_path)
      expect(menu).not_to include(admin_organizations_path)
      expect(menu).not_to include(federation_peers_path)
    end
  end

  it "offers an administrator Organizations and Federation Peers" do
    sign_in_as(create(:user, :admin))
    get root_path
    expect(response.body).to include(admin_organizations_path, federation_peers_path)
  end

  describe "the boundary list" do
    before { grant_read_on(mine) }

    it "lists and counts only the user's boundary" do
      sign_in_as(user)
      get authorization_boundaries_path(view: "list")
      expect(response.body).to include("Mine System")
      expect(response.body).not_to include("Theirs System")
      tiles = Nokogiri::HTML(response.body).css(".sparc-hero-tile-count").map { |t| t.text.strip }
      expect(tiles.first).to eq("1")
    end

    it "shows a read-only user no Edit, Delete or New" do
      sign_in_as(user)
      get authorization_boundaries_path(view: "list")
      expect(response.body).not_to include(edit_authorization_boundary_path(mine))
      expect(response.body).not_to include("New Authorization Boundary")
      expect(Nokogiri::HTML(response.body).at_css("form[action='#{authorization_boundary_path(mine)}']")).to be_nil
    end

    it "shows Edit to a boundary writer, and New only with an instance-level write" do
      grant_permission(user, "authorization_boundaries.write", authorization_boundary: mine)
      sign_in_as(user)
      get authorization_boundaries_path(view: "list")
      expect(response.body).to include(edit_authorization_boundary_path(mine))
      expect(response.body).not_to include("New Authorization Boundary")
    end

    it "colours a status the same in both views, from ab_status_variant" do
      sign_in_as(user)
      # active is "info" in ab_status_variant; the card view called it success,
      # the table badge-ok.
      get authorization_boundaries_path(view: "list")
      expect(response.body).to include("sparc-status--info")
      get authorization_boundaries_path(view: "card")
      expect(response.body).to include("sparc-status--info")
    end

    it "labels environments as environments" do
      sign_in_as(user)
      get authorization_boundaries_path(view: "list")
      expect(response.body).to include("<th>Environments</th>")
      expect(response.body).not_to include("<th>Boundaries</th>")
    end
  end

  describe "Members: distinct people, both ways of granting access" do
    let(:person) { create(:user, email: "person@example.org") }

    it "counts a person with two roles once, and someone recorded both ways once" do
      grant_permission(person, "ssp.read", authorization_boundary: mine)
      grant_permission(person, "ssp.write", authorization_boundary: mine)
      create(:authorization_boundary_membership, authorization_boundary: mine,
             user_email: "PERSON@example.org", user_name: "Person", role: "isso")
      create(:authorization_boundary_membership, authorization_boundary: mine,
             user_email: "other@example.org", user_name: "Other", role: "system_owner")

      expect(mine.people_count).to eq(2)
    end
  end

  describe "the Completeness checklist" do
    def role(name, display) = Role.find_by(name: name) || create(:role, :authorization_boundary_scoped, name: name, display_name: display)

    before do
      { "system_owner" => "System Owner", "isso" => "ISSO", "authorizing_official" => "Authorizing Official" }.each do |key, label|
        create(:user_role, user: create(:user), role: role(key, label), authorization_boundary: mine)
      end
    end

    it "counts personnel assigned by role, with display names, and the API says the same" do
      personnel = BoundaryReadinessService.new(mine).sections.find { |s| s.key == :personnel }
      expect(personnel.status).to eq(:complete)
      expect(personnel.count).to eq(3)
      expect(personnel.detail).to include("Authorizing Official", "System Owner")
      expect(personnel.detail).not_to include("authorizing_official")
      expect(personnel.roles).to include("authorizing_official")

      admin = create(:user, :admin)
      token = ApiToken.generate!(user: admin, name: "t")
      get "/api/v1/authorization_boundaries/#{mine.slug}/readiness",
          headers: { "Authorization" => "Bearer #{token.plaintext_token}" }
      api = response.parsed_body.dig("data", "sections").find { |s| s["key"] == "personnel" }
      expect(api["status"]).to eq("complete")
      expect(api["roles"]).to include("authorizing_official")
    end

    it "keeps an optional absence out of the red count" do
      summary = BoundaryReadinessService.new(mine).report[:summary]
      leveraged = BoundaryReadinessService.new(mine).sections.find { |s| s.key == :leveraged }
      expect(leveraged.status).to eq(:absent)
      expect(summary[:optional_none]).to eq(1)

      sign_in_as(create(:user, :admin))
      get authorization_boundary_path(mine)
      expect(response.body).to include("None (optional)")
    end

    it "sends the POA&M tile to this boundary's POA&Ms" do
      create(:poam_document, authorization_boundary: mine)
      sign_in_as(create(:user, :admin))
      get authorization_boundary_path(mine)
      # The tile itself: the sidebar links the same URL, so a page-wide match
      # would pass with the tile still pointing at every boundary's POA&Ms.
      tile = Nokogiri::HTML(response.body).css("a.sparc-hero-tile-link")
                     .find { |a| a.text.include?("POA&Ms") }
      expect(tile["href"]).to eq(BoundaryScopedList.path(:poam, mine))
    end
  end
end
