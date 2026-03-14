require "rails_helper"

RSpec.describe PoamDocument, type: :model do
  describe "validations" do
    subject { build(:poam_document) }

    it { is_expected.to validate_presence_of(:name) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:authorization_boundary).optional }
    it { is_expected.to have_many(:poam_items).dependent(:delete_all) }
    it { is_expected.to have_many(:poam_risks).dependent(:delete_all) }
    it { is_expected.to have_many(:poam_observations).dependent(:delete_all) }
    it { is_expected.to have_many(:poam_findings).dependent(:delete_all) }
    it { is_expected.to have_one_attached(:file) }
  end

  describe "concerns" do
    it "includes OscalMetadata" do
      expect(PoamDocument.ancestors).to include(OscalMetadata)
    end

    it "includes SafeDestroyable" do
      expect(PoamDocument.ancestors).to include(SafeDestroyable)
    end
  end

  describe "enums" do
    it "defines status enum" do
      expect(PoamDocument.statuses).to eq(
        "pending" => "pending",
        "processing" => "processing",
        "completed" => "completed",
        "failed" => "failed"
      )
    end
  end

  describe "deletion protection" do
    it "always allows deletion (leaf node)" do
      poam = create(:poam_document)
      expect(poam.destroy).to be_truthy
    end

    it "allows deletion even with child items" do
      poam = create(:poam_document)
      create(:poam_item, poam_document: poam)
      create(:poam_risk, poam_document: poam)
      create(:poam_observation, poam_document: poam)
      create(:poam_finding, poam_document: poam)

      expect(poam.destroy).to be_truthy
    end
  end

  describe "#to_json_data" do
    let(:poam) { create(:poam_document, name: "Test POA&M") }

    it "returns a hash with document metadata" do
      data = poam.to_json_data

      expect(data[:document_name]).to eq("Test POA&M")
      expect(data[:risks_count]).to eq(0)
      expect(data[:observations_count]).to eq(0)
      expect(data[:findings_count]).to eq(0)
      expect(data[:items]).to be_an(Array)
    end

    it "includes counts for associated records" do
      create(:poam_risk, poam_document: poam)
      create(:poam_observation, poam_document: poam)
      create(:poam_finding, poam_document: poam)

      data = poam.to_json_data

      expect(data[:risks_count]).to eq(1)
      expect(data[:observations_count]).to eq(1)
      expect(data[:findings_count]).to eq(1)
    end
  end
end
