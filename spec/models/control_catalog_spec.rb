require "rails_helper"

RSpec.describe ControlCatalog, type: :model do
  describe "validations" do
    subject { build(:control_catalog) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_uniqueness_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:control_families).dependent(:destroy) }
    it { is_expected.to have_many(:catalog_controls).through(:control_families) }
  end

  describe "OscalMetadata concern" do
    let(:catalog) { create(:control_catalog, :with_metadata) }

    it "includes OscalMetadata" do
      expect(ControlCatalog.ancestors).to include(OscalMetadata)
    end

    it "provides oscal_roles accessor" do
      expect(catalog.oscal_roles).to be_an(Array)
      expect(catalog.oscal_roles.first["id"]).to eq("prepared-by")
    end

    it "provides oscal_parties accessor" do
      expect(catalog.oscal_parties).to be_an(Array)
      expect(catalog.oscal_parties.first["name"]).to eq("Test Org")
    end

    it "builds OSCAL metadata hash for export" do
      metadata = catalog.build_oscal_metadata
      expect(metadata["title"]).to eq(catalog.name)
      expect(metadata["oscal-version"]).to eq("1.1.2")
      expect(metadata["roles"]).to be_present
    end
  end

  describe "#oscal_document_version" do
    it "returns the version attribute" do
      catalog = build(:control_catalog, version: "5.1.1")
      expect(catalog.oscal_document_version).to eq("5.1.1")
    end
  end

  describe "#total_controls" do
    it "returns the count of catalog controls" do
      catalog = create(:control_catalog)
      expect(catalog.total_controls).to eq(0)
    end
  end
end
