require "rails_helper"

RSpec.describe SarDocument, type: :model do
  subject { build(:sar_document) }

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary).optional }
    it { is_expected.to belong_to(:sap_document).optional }
    it { is_expected.to have_many(:sar_controls).dependent(:delete_all) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }

    it "validates file_type inclusion" do
      doc = build(:sar_document, file_type: "invalid")
      expect(doc).not_to be_valid
    end

    it "validates creation_method inclusion" do
      doc = build(:sar_document, creation_method: "invalid")
      expect(doc).not_to be_valid
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(SarDocument.statuses).to include("pending", "processing", "completed", "failed")
    end
  end

  describe "#wizard_created?" do
    it "returns true for wizard creation method" do
      doc = build(:sar_document, :wizard)
      expect(doc.wizard_created?).to be true
    end

    it "returns false for non-wizard creation method" do
      doc = build(:sar_document)
      expect(doc.wizard_created?).to be false
    end
  end

  describe "#oscal_imported?" do
    it "returns true for oscal_import creation method" do
      doc = build(:sar_document, :oscal_import)
      expect(doc.oscal_imported?).to be true
    end
  end

  describe "#enriched?" do
    it "returns false for a bare document" do
      doc = build(:sar_document)
      expect(doc.enriched?).to be false
    end

    it "returns true when description is present" do
      doc = build(:sar_document, :enriched)
      expect(doc.enriched?).to be true
    end
  end

  describe "#to_json_data" do
    it "returns structured hash with document name and controls" do
      doc = create(:sar_document)
      result = doc.to_json_data
      expect(result).to include(:document_name, :controls)
      expect(result[:document_name]).to eq(doc.name)
    end
  end
end
