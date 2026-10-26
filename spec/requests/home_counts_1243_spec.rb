# frozen_string_literal: true

require "rails_helper"

# #1243 — the homepage's counts live on the layer cards, each a badge linking
# to the same page as the card's View button, and each the number THAT page
# shows this user (owner, 2026-10-22: counts show only what the user has
# permission to see). The thin inventory tiles above the cards show the same
# counts, each a link to the same list as its card;
# #1243 removed them in v1.17.2 by mistake, and they are restored.
#
# NIST 800-53: AC-3, AC-4 (a count must not disclose other boundaries' records).
RSpec.describe "Homepage counts (#1243)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:mine)   { create(:authorization_boundary, name: "Mine") }
  let(:theirs) { create(:authorization_boundary, name: "Theirs") }
  let(:user)   { create(:user) }
  # A method, not a memoized let: an example that requests twice must
  # read the SECOND response.
  def page = Nokogiri::HTML(response.body)

  def badge(key) = page.at_css("a[data-home-count='#{key}']")

  # The figure the index page itself shows (its @total_count tile).
  def index_count(path)
    get path
    expect(response).to have_http_status(:ok)
    controller.instance_variable_get(:@total_count)
  end

  # A method, not a constant: a constant in a describe block is defined on
  # Object and leaks into every other spec.
  def boundary_types
    { ssp_documents: :ssp_document, sap_documents: :sap_document,
      sar_documents: :sar_document, poam_documents: :poam_document }
  end

  def card_new_links = page.css(".sparc-section-card a").select { |a| a.text.strip == "New" }.map { |a| a["href"] }

  # The inventory above the cards, as { label => count text }.
  def inventory
    page.css("[data-home-inventory] a.sparc-inventory-tile").to_h do |tile|
      [ tile.at_css(".sparc-inventory-name").text.strip, tile.at_css(".sparc-inventory-count").text.strip ]
    end
  end

  def tile(key) = page.at_css("[data-home-inventory] a[data-home-tile='#{key}']")

  # Inventory tiles that have a card badge of their own.
  def tile_badges
    { "Catalogs" => :control_catalogs, "Baselines" => :profile_documents, "Mappings" => :control_mappings,
      "SSPs" => :ssp_documents, "CDEFs" => :cdef_documents, "Converters" => :converters,
      "SAPs" => :sap_documents, "Evidence" => :evidences, "SARs" => :sar_documents,
      "POA&Ms" => :poam_documents, "Auth Boundaries" => :authorization_boundaries }
  end

  before do
    boundary_types.each_value do |factory|
      create(factory, authorization_boundary: mine)
      create_list(factory, 2, authorization_boundary: theirs)
    end
    create(:evidence, authorization_boundary: mine)
    create_list(:evidence, 2, authorization_boundary: theirs)
    create(:evidence, authorization_boundary: nil) # instance-wide: Evidence's global_fallback
  end

  describe "a non-administrator assigned to one boundary" do
    before do
      %w[ssp.read sap.read sar.read poam.read evidence.read authorization_boundaries.read].each do |key|
        grant_permission(user, key, authorization_boundary: mine)
      end
      sign_in_as(user)
    end

    it "sees, on each badge, exactly what that card's index page shows them" do
      paths = {
        ssp_documents: ssp_documents_path, sap_documents: sap_documents_path,
        sar_documents: sar_documents_path, poam_documents: poam_documents_path,
        evidences: evidences_path, authorization_boundaries: authorization_boundaries_path,
        control_catalogs: control_catalogs_path, profile_documents: profile_documents_path,
        control_mappings: control_mappings_path, cdef_documents: cdef_documents_path,
        converters: converters_path
      }
      expected = paths.transform_values { |path| index_count(path) }

      get root_path

      paths.each do |key, path|
        expect(badge(key)).to be_present, "no badge for #{key}"
        expect(badge(key).text.delete(",").to_i).to eq(expected[key]), "#{key}: badge differs from its index page"
        expect(badge(key)["href"]).to eq(path)
      end
    end

    it "is never shown another boundary's records" do
      get root_path

      boundary_types.each_key { |key| expect(badge(key).text).to eq("1"), key.to_s }
      expect(badge(:evidences).text).to eq("2") # own + the instance-wide one
      expect(badge(:authorization_boundaries).text).to eq("1")
    end

    it "is not offered the Organizations card, an administrator screen" do
      get root_path

      expect(badge(:organizations)).to be_nil
      expect(response.body).not_to include(admin_organizations_path)
    end

    it "sees the inventory tiles above the cards, each matching its card's badge" do
      get root_path

      expect(page.at_css("[data-home-inventory]")).to be_present
      expect(inventory.keys).to eq([ "Catalogs", "Families", "Controls", "Baselines", "Mappings",
                                    "SSPs", "CDEFs", "Converters",
                                    "SAPs", "Evidence", "SARs", "POA&Ms",
                                    "Auth Boundaries" ])
      tile_badges.each do |label, key|
        expect(inventory[label]).to eq(badge(key).text), label
        expect(tile(key)["href"]).to eq(badge(key)["href"]), "#{label}: tile and card open different lists"
      end
      expect(tile(:families)["href"]).to eq(control_catalogs_path)
      expect(tile(:controls)["href"]).to eq(control_catalogs_path)
      expect(inventory["Families"]).to eq(ActiveSupport::NumberHelper.number_to_delimited(ControlCatalog.family_count))
      expect(inventory["Controls"]).to eq(ActiveSupport::NumberHelper.number_to_delimited(ControlCatalog.control_count))
    end

    it "is offered New only where the create action would admit them" do
      get root_path

      expect(card_new_links).to be_empty
    end

    it "is offered New on a card once they may create there" do
      grant_permission(user, "ssp.write", authorization_boundary: mine)
      grant_permission(user, "catalogs.write")

      get root_path

      expect(card_new_links).to contain_exactly(new_ssp_document_path, new_control_catalog_path)
    end

    it "lays every card out the same way: icon, count, title, buttons" do
      create(:control_catalog)
      get root_path

      page.css(".sparc-section-card .card-body").each do |body|
        kinds = body.element_children.map do |el|
          if el["class"].to_s.include?("sparc-count-badge") then :count
          elsif el.name == "h5" then :title
          elsif el.css("a.sparc-action").any? then :buttons
          else :icon
          end
        end
        expect(kinds).to eq(%i[icon count title buttons]), body.at_css("h5")&.text
      end
      # Families and controls are the tiles' to show; no card carries a breakdown.
      expect(page.css(".sparc-section-card .card-body").size).to eq(11) # every card this user is offered
      expect(page.css(".sparc-section-card").text).not_to include("families")
    end
  end

  describe "an administrator" do
    before { sign_in_as(create(:user, :admin)) }

    it "sees full totals, the Organizations card, and every New" do
      get root_path

      expect(badge(:ssp_documents).text).to eq("3")
      expect(badge(:evidences).text).to eq("4")
      expect(badge(:organizations).text).to eq(Organization.count.to_s)
      expect(badge(:organizations)["href"]).to eq(admin_organizations_path)
      expect(card_new_links.size).to eq(12)
    end

    it "sees the full inventory, Organizations included, at instance totals" do
      get root_path

      expect(inventory.keys).to include("Organizations")
      expect(inventory["Organizations"]).to eq(ActiveSupport::NumberHelper.number_to_delimited(Organization.count))
      expect(tile(:organizations)["href"]).to eq(admin_organizations_path)
      expect(inventory["SSPs"]).to eq("3")
      expect(inventory["Evidence"]).to eq("4")
    end
  end

  describe "with auth disabled" do
    before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false) }

    it "counts everything and shows the Organizations card" do
      get root_path

      expect(badge(:ssp_documents).text).to eq("3")
      expect(badge(:organizations)).to be_present
    end
  end

  describe "BoundaryScopedDocument.index_relation" do
    it "is the relation the controller's own index uses" do
      grant_permission(user, "ssp.read", authorization_boundary: mine)

      relation = BoundaryScopedDocument.index_relation(SspDocumentsController, user)

      expect(relation.to_a).to contain_exactly(SspDocument.find_by!(authorization_boundary: mine))
    end
  end
end
