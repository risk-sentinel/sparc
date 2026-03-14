require "rails_helper"

RSpec.describe SapDocument, type: :model do
  describe "validations" do
    subject { build(:sap_document) }

    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to have_many(:sap_controls).dependent(:delete_all) }
    it { is_expected.to belong_to(:ssp_document).optional }
    it { is_expected.to belong_to(:profile_document).optional }
    it { is_expected.to belong_to(:authorization_boundary).optional }
    it { is_expected.to have_one_attached(:file) }
  end

  describe "concerns" do
    it "includes OscalMetadata" do
      expect(SapDocument.ancestors).to include(OscalMetadata)
    end

    it "includes SafeDestroyable" do
      expect(SapDocument.ancestors).to include(SafeDestroyable)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(SapDocument.statuses).to eq(
        "pending" => "pending",
        "processing" => "processing",
        "completed" => "completed",
        "failed" => "failed"
      )
    end
  end

  describe "deletion protection" do
    it "prevents deletion when a SarDocument references the SAP" do
      sap = create(:sap_document)
      create(:sar_document, sap_document: sap)

      expect(sap.destroy).to be_falsey
      expect(sap.errors[:base].first).to match(/Cannot delete sap document/)
    end

    it "allows deletion when no SAR documents are linked" do
      sap = create(:sap_document)
      expect(sap.destroy).to be_truthy
    end
  end

  describe "#to_json_data" do
    let(:sap) { create(:sap_document, name: "Test SAP", assessment_type: "annual") }
    let!(:control) { create(:sap_control, sap_document: sap, control_id: "AC-1") }

    it "returns a hash with document metadata and controls" do
      data = sap.to_json_data

      expect(data[:document_name]).to eq("Test SAP")
      expect(data[:assessment_type]).to eq("annual")
      expect(data[:controls]).to be_an(Array)
      expect(data[:controls].length).to eq(1)
      expect(data[:controls].first[:control_id]).to eq("AC-1")
    end
  end

  describe "#method_counts" do
    let(:sap) { create(:sap_document) }

    before do
      create(:sap_control, sap_document: sap, assessment_method: "examine")
      create(:sap_control, sap_document: sap, assessment_method: "examine")
      create(:sap_control, sap_document: sap, assessment_method: "test")
    end

    it "returns method distribution" do
      counts = sap.method_counts
      expect(counts["examine"]).to eq(2)
      expect(counts["test"]).to eq(1)
    end
  end

  describe "#status_counts" do
    let(:sap) { create(:sap_document) }

    before do
      create(:sap_control, sap_document: sap, assessment_status: "planned")
      create(:sap_control, sap_document: sap, assessment_status: "planned")
      create(:sap_control, sap_document: sap, assessment_status: "completed")
    end

    it "returns status distribution" do
      counts = sap.status_counts
      expect(counts["planned"]).to eq(2)
      expect(counts["completed"]).to eq(1)
    end
  end
end
