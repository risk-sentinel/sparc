# frozen_string_literal: true

require "rails_helper"

# The custom-controls samples in docs/api/samples are what an organization
# copies to start its own controls, so they must stay valid OSCAL and the
# catalog must import into SPARC as written.
RSpec.describe "docs/api/samples custom-controls skeletons" do
  let(:samples) { Rails.root.join("docs/api/samples") }

  def sample(name) = JSON.parse(File.read(samples.join(name)))

  it "has a catalog the OSCAL 1.2.3 schema accepts" do
    result = OscalSchemaValidationService.validate(:catalog, sample("custom-controls-catalog.json"), version: "1.2.3")
    expect(result.errors).to be_empty
  end

  it "has a profile the OSCAL 1.2.3 schema accepts" do
    result = OscalSchemaValidationService.validate(:profile, sample("custom-controls-profile.json"), version: "1.2.3")
    expect(result.errors).to be_empty
  end

  describe "importing the catalog" do
    subject(:catalog) do
      CatalogImportService.call(File.open(samples.join("custom-controls-catalog.json")), "custom-controls-catalog.json")[:catalog]
    end

    it "creates its family and its control and enhancement, labelled" do
      expect(catalog.control_families.pluck(:code, :name)).to eq([ [ "DP", "Data Protection" ] ])
      expect(catalog.catalog_controls.where(control_id: %w[dp-1 dp-1.1]).order(:control_id).pluck(:control_id, :label, :title)).to eq(
        [ [ "dp-1", "DP-1", "Data Retention Review" ], [ "dp-1.1", "DP-1(1)", "Automated Retention Enforcement" ] ]
      )
    end

    it "raises no import warning, so a copy starts clean" do
      expect(CatalogImportValidationService.new(catalog).validate["import_warnings"]).to be_empty
    end
  end
end
