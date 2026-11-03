# frozen_string_literal: true

require "rails_helper"

# #1329 — with its baseline naming no catalog, an SSP control listed each item
# under "What this baseline requires" once per loaded catalog (ac-1a four times
# on an instance with four catalogs). Each item is now listed once, from the
# catalog the control's own text comes from.
RSpec.describe "SSP baseline items from one catalog (#1329)", type: :request do
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def catalog_with(version, tag)
    catalog = create(:control_catalog, oscal_version: version)
    family = create(:control_family, control_catalog: catalog)
    create(:catalog_control, control_family: family, control_id: "ac-1", title: "Policy (#{tag})")
    create(:catalog_control, control_family: family, control_id: "ac-1a", title: "Develop (#{tag})")
    create(:catalog_control, control_family: family, control_id: "ac-1b", title: "Review (#{tag})")
    catalog
  end

  let!(:older) { catalog_with("1.0.4", "older") }
  let!(:newer) { catalog_with("1.1.2", "newer") }

  let(:boundary) { create(:authorization_boundary) }
  let(:writer) do
    create(:user).tap do |u|
      grant_permission(u, "ssp.read", authorization_boundary: boundary)
      grant_permission(u, "ssp.write", authorization_boundary: boundary)
    end
  end

  def ssp_on(catalog)
    profile = create(:profile_document, control_catalog: catalog, lifecycle_status: "published",
                                        resolved_catalog_json: { "catalog" => { "controls" => [] } })
    create(:ssp_document, authorization_boundary: boundary, profile_document: profile, status: "completed").tap do |ssp|
      ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
    end
  end

  # Each "What this baseline requires" list on the page, as [id, title] pairs
  # (the page shows ids upper-case).
  def listed_items
    Nokogiri::HTML(response.body).css(".sparc-sub-parts-section").map do |section|
      section.css(".sparc-sub-part-item").map do |item|
        [ item.at_css(".sparc-sub-part-id").text.strip.downcase, item.at_css(".sparc-sub-part-title")&.text&.strip ]
      end
    end
  end

  it "lists each item once, from the catalog the control's text comes from, when the baseline names no catalog" do
    sign_in_as(writer)
    get ssp_document_path(ssp_on(nil))

    expect(response).to have_http_status(:ok)
    expect(listed_items).not_to be_empty
    expect(listed_items).to all(eq([ [ "ac-1a", "Develop (newer)" ], [ "ac-1b", "Review (newer)" ] ]))
  end

  it "still lists the linked catalog's items when the baseline names one" do
    sign_in_as(writer)
    get ssp_document_path(ssp_on(older))

    expect(listed_items).not_to be_empty
    expect(listed_items).to all(eq([ [ "ac-1a", "Develop (older)" ], [ "ac-1b", "Review (older)" ] ]))
  end
end
